import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/hardware_data_monitor.dart';

class HardwareMonitorView extends StatefulWidget {
  const HardwareMonitorView({super.key});

  @override
  State<HardwareMonitorView> createState() => _HardwareMonitorViewState();
}

class _HardwareMonitorViewState extends State<HardwareMonitorView> {
  final _events = <HardwareDataEvent>[];
  StreamSubscription<HardwareDataEvent>? _subscription;

  @override
  void initState() {
    super.initState();
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
    _subscription?.cancel();
    super.dispose();
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
                onPressed: _events.isEmpty
                    ? null
                    : () => setState(_events.clear),
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
