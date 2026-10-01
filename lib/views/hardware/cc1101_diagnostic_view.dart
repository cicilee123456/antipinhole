import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/cc1101_diagnostic_sample.dart';
import '../../services/cc1101_diagnostic_service.dart';

class Cc1101DiagnosticView extends StatefulWidget {
  const Cc1101DiagnosticView({super.key});

  @override
  State<Cc1101DiagnosticView> createState() => _Cc1101DiagnosticViewState();
}

class _Cc1101DiagnosticViewState extends State<Cc1101DiagnosticView> {
  static const _storageKey = 'cc1101_diagnostic_samples';
  final _service = Cc1101DiagnosticService();
  final _samples = <Cc1101DiagnosticSample>[];
  StreamSubscription<Cc1101DiagnosticSample>? _subscription;
  String? _error;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSamples());
  }

  Cc1101DiagnosticSample? get _latest => _samples.isEmpty ? null : _samples.last;

  Future<void> _start() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _error = null;
    });
    await _subscription?.cancel();
    _subscription = _service.samples.listen(
      _addSample,
      onError: (Object error) {
        if (mounted) setState(() => _error = error.toString());
      },
    );
    await _service.start();
  }

  Future<void> _stop() async {
    await _service.stop();
    await _subscription?.cancel();
    _subscription = null;
    if (mounted) setState(() => _isRunning = false);
  }

  void _addSample(Cc1101DiagnosticSample sample) {
    if (!mounted) return;
    setState(() {
      _samples.add(sample);
      if (_samples.length > 200) _samples.removeAt(0);
      _error = null;
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
    if (!mounted) return;
    setState(() {
      _samples
        ..clear()
        ..addAll(restored.length > 200
            ? restored.sublist(restored.length - 200)
            : restored);
    });
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
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sample = _latest;
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
                      Text('CC1101 診斷模式', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text('此頁只收集無線訊號資料，不會觸發熱成像異常告警。'),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _isRunning ? null : _start,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('開始測試'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _isRunning ? _stop : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('停止測試'),
                          ),
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
                      Text(_isRunning ? '測試中，每 500 ms 讀取一次' : '測試尚未開始'),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
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
                      Text('原始紀錄', style: Theme.of(context).textTheme.titleMedium),
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
                                  final item = _samples[_samples.length - index - 1];
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
            _Metric(label: '距離', value: _formatNumber(sample?.distanceMeters, ' m')),
            _Metric(label: '資料時間', value: sample == null ? '--' : _format(sample!.capturedAt)),
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
  return value == null ? '--' : value ? 'OK' : 'FAIL';
}

String _formatPackets(Cc1101DiagnosticSample? sample) {
  if (sample?.receivedPackets == null && sample?.lostPackets == null) return '--';
  return '${sample?.receivedPackets ?? '--'} / ${sample?.lostPackets ?? '--'}';
}

String _format(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
}
