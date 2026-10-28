import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/hardware_data_monitor.dart';
import '../../services/detection_settings.dart';
import '../../models/scan_data.dart';

class HardwareMonitorView extends StatefulWidget {
  const HardwareMonitorView({super.key});

  @override
  State<HardwareMonitorView> createState() => _HardwareMonitorViewState();
}

class _HardwareMonitorViewState extends State<HardwareMonitorView> {
  final _events = <HardwareDataEvent>[];
  final _detectionSettings = DetectionSettings.instance;
  StreamSubscription<HardwareDataEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _detectionSettings.addListener(_onDetectionSettingsChanged);
    unawaited(_detectionSettings.load());
    _subscription = HardwareDataMonitor.instance.events.listen((event) {
      if (!mounted) return;
      setState(() {
        _events.insert(0, event);
        if (_events.length > 200) _events.removeLast();
      });
    });
  }

  @override
  void dispose() {
    _detectionSettings.removeListener(_onDetectionSettingsChanged);
    _subscription?.cancel();
    super.dispose();
  }

  void _onDetectionSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _copyAll() async {
    final text = _events.map(_formatEvent).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('監控資料已複製')),
      );
    }
  }

  String _formatEvent(HardwareDataEvent event) {
    final status = event.isParsed ? '解析成功' : '解析失敗：${event.error}';
    return '[${event.timestamp.toIso8601String()}] '
        '${event.source} $status\n${event.rawText}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetectionSettingsCard(settings: _detectionSettings),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Expanded(child: Text('即時接收 Raw Data 與解析狀態')),
              IconButton(
                tooltip: '複製資料',
                onPressed: _events.isEmpty ? null : _copyAll,
                icon: const Icon(Icons.copy_all),
              ),
              IconButton(
                tooltip: '清空紀錄',
                onPressed:
                    _events.isEmpty ? null : () => setState(_events.clear),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: _events.isEmpty
              ? const Center(child: Text('尚未收到硬體資料'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _events.length,
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    return Card(
                      color: event.isParsed
                          ? null
                          : Theme.of(context).colorScheme.errorContainer,
                      child: ExpansionTile(
                        leading: Icon(
                          event.isParsed ? Icons.check_circle : Icons.error,
                          color: event.isParsed ? Colors.green : Colors.red,
                        ),
                        title: Text(
                          '${event.source} · '
                          '${event.isParsed ? '解析成功' : '解析失敗'}',
                        ),
                        subtitle: Text(event.timestamp.toLocal().toString()),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(event.rawText),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DetectionSettingsCard extends StatelessWidget {
  const _DetectionSettingsCard({required this.settings});

  final DetectionSettings settings;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '偵測設定',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<HeatEnvironmentMode>(
              segments: const [
                ButtonSegment(
                  value: HeatEnvironmentMode.heatSource,
                  label: Text('有熱源'),
                  icon: Icon(Icons.local_fire_department),
                ),
                ButtonSegment(
                  value: HeatEnvironmentMode.noHeatSource,
                  label: Text('無熱源'),
                  icon: Icon(Icons.ac_unit),
                ),
              ],
              selected: {settings.environmentMode},
              onSelectionChanged: (selection) {
                unawaited(settings.setEnvironmentMode(selection.first));
              },
            ),
            const Divider(height: 24),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('熱成像偵測'),
              subtitle: Text(
                settings.thermalEnabled ? '已啟用' : '未啟用，結果可信度降低且不使用熱成像判定',
              ),
              value: settings.thermalEnabled,
              onChanged: (enabled) {
                unawaited(settings.setThermalEnabled(enabled));
              },
            ),
          ],
        ),
      ),
    );
  }
}
