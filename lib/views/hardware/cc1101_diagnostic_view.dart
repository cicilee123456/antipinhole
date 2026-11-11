import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/cc1101_diagnostic_sample.dart';
import '../../services/hardware_connection_service.dart';
import '../../services/hardware_data_monitor.dart';

class Cc1101DiagnosticView extends StatefulWidget {
  const Cc1101DiagnosticView({super.key});

  @override
  State<Cc1101DiagnosticView> createState() => _Cc1101DiagnosticViewState();
}

class _Cc1101DiagnosticViewState extends State<Cc1101DiagnosticView> {
  static const _storageKey = 'cc1101_diagnostic_samples';
  final _samples = <Cc1101DiagnosticSample>[];
  HardwareConnectionService? _service;
  StreamSubscription<HardwareDataEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSamples());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = HardwareConnectionScope.of(context);
    if (identical(service, _service)) return;
    _subscription?.cancel();
    _service = service;
    final latestSample = service.latestCc1101Sample;
    if (latestSample != null) _addSample(latestSample);
    _subscription = service.events.listen(_onHardwareEvent);
  }

  Cc1101DiagnosticSample? get _latest =>
      _samples.isEmpty ? null : _samples.last;

  void _onHardwareEvent(HardwareDataEvent event) {
    final sample = event.cc1101Sample;
    if (sample != null) _addSample(sample);
  }

  void _addSample(Cc1101DiagnosticSample sample) {
    if (!mounted) return;
    if (_samples.any((item) => item.toJsonLine() == sample.toJsonLine())) {
      return;
    }
    setState(() {
      _samples.add(sample);
      if (_samples.length > 200) _samples.removeAt(0);
    });
    unawaited(_saveSamples());
  }

  Future<void> _loadSamples() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getStringList(_storageKey) ?? const <String>[];
    final restored = <Cc1101DiagnosticSample>[];
    for (final line in saved) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          restored.add(Cc1101DiagnosticSample.fromJson(decoded));
        }
      } on FormatException {
        // 忽略無法恢復的單筆紀錄，保留其他有效資料。
      }
    }
    for (final sample in _samples) {
      if (!restored.any((item) => item.toJsonLine() == sample.toJsonLine())) {
        restored.add(sample);
      }
    }
    final latestSample = _service?.latestCc1101Sample;
    if (latestSample != null &&
        !restored.any(
            (sample) => sample.toJsonLine() == latestSample.toJsonLine())) {
      restored.add(latestSample);
    }
    if (!mounted) return;
    setState(() {
      _samples
        ..clear()
        ..addAll(restored.length > 200
            ? restored.sublist(restored.length - 200)
            : restored);
    });
    if (latestSample != null) unawaited(_saveSamples());
  }

  Future<void> _saveSamples() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _storageKey,
      _samples.map((sample) => sample.toJsonLine()).toList(growable: false),
    );
  }

  Future<void> _copySamples() async {
    final payload = const JsonEncoder.withIndent('  ').convert(
      _samples.map((sample) => jsonDecode(sample.toJsonLine())).toList(),
    );
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已複製 ${_samples.length} 筆 CC1101 原始紀錄')),
    );
  }

  void _clearSamples() {
    setState(() => _samples.clear());
    unawaited(_saveSamples());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = HardwareConnectionScope.of(context);
    final sample = _latest;
    final activeConnection = service.activeConnection;
    final failedConnection = service.failedConnection;
    final connectionStatus = activeConnection == null
        ? service.isSimulating
            ? '模擬資料中'
            : failedConnection == null
                ? '等待硬體監控頁建立連線'
                : '${_connectionName(failedConnection)} · Error: ${service.stateFor(failedConnection).error}'
        : '${_connectionName(activeConnection)} · ${_statusLabel(service.stateFor(activeConnection).status)}';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CC1101 診斷模式',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                          '本頁只顯示共用連線服務收到的 CC1101 資料；連線請回到「硬體監控」頁操作。高風險 SOP 由共用熱成像風險規則統一觸發。'),
                      const SizedBox(height: 12),
                      Text(connectionStatus),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _samples.isEmpty ? null : _copySamples,
                            icon: const Icon(Icons.copy),
                            label: const Text('複製 JSON'),
                          ),
                          TextButton.icon(
                            onPressed: _samples.isEmpty ? null : _clearSamples,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('清除紀錄'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(activeConnection != null || service.isSimulating
                          ? '即時資料會自動加入下方紀錄'
                          : '尚未連線'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _MetricsCard(sample: sample),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('原始紀錄',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('目前保留 ${_samples.length} / 200 筆，最新資料會自動加入。'),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 180,
                        child: _samples.isEmpty
                            ? const Center(child: Text('尚未收到 CC1101 資料'))
                            : ListView.builder(
                                itemCount: _samples.length,
                                itemBuilder: (context, index) {
                                  final item =
                                      _samples[_samples.length - index - 1];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      '${_format(item.capturedAt)}  RSSI ${_formatNumber(item.rssi, ' dBm')}',
                                    ),
                                    subtitle: Text(
                                      'LQI ${_formatNumber(item.lqi, '')} | CRC ${_formatCrc(item.crcOk)} | PER ${_formatPercent(item.per)}',
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.sample});

  final Cc1101DiagnosticSample? sample;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 32,
          runSpacing: 20,
          children: [
            _Metric(label: 'RSSI', value: _formatNumber(sample?.rssi, ' dBm')),
            _Metric(label: 'LQI', value: _formatNumber(sample?.lqi, '')),
            _Metric(label: 'CRC', value: _formatCrc(sample?.crcOk)),
            _Metric(label: '封包數', value: _formatPackets(sample)),
            _Metric(label: 'PER', value: _formatPercent(sample?.per)),
            _Metric(
                label: '距離',
                value: _formatNumber(sample?.distanceMeters, ' m')),
            _Metric(
                label: '資料時間',
                value: sample == null ? '--' : _format(sample!.capturedAt)),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

String _formatNumber(double? value, String suffix) {
  return value == null ? '--' : '${value.toStringAsFixed(1)}$suffix';
}

String _formatPercent(double? value) {
  return value == null ? '--' : '${(value * 100).toStringAsFixed(2)}%';
}

String _formatCrc(bool? value) {
  return value == null
      ? '--'
      : value
          ? 'OK'
          : 'FAIL';
}

String _formatPackets(Cc1101DiagnosticSample? sample) {
  if (sample?.receivedPackets == null && sample?.lostPackets == null) {
    return '--';
  }
  return '${sample?.receivedPackets ?? '--'} / ${sample?.lostPackets ?? '--'}';
}

String _connectionName(HardwareConnectionType type) => switch (type) {
      HardwareConnectionType.esp32Bluetooth => 'CC1101_BLE',
    };

String _statusLabel(HardwareConnectionStatus status) => switch (status) {
      HardwareConnectionStatus.disconnected => 'Disconnected',
      HardwareConnectionStatus.connecting => 'Connecting',
      HardwareConnectionStatus.connected => 'Connected',
      HardwareConnectionStatus.error => 'Error',
    };

String _format(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
}
