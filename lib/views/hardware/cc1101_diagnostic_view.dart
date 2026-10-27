import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geolocator/geolocator.dart';

import '../../models/detection_record.dart';
import '../../models/cc1101_diagnostic_sample.dart';
import '../../services/cc1101_diagnostic_service.dart';
import '../../services/database_helper.dart';
import '../thermal/sop_dialog.dart';

class Cc1101DiagnosticView extends StatefulWidget {
  const Cc1101DiagnosticView({super.key});

  @override
  State<Cc1101DiagnosticView> createState() => _Cc1101DiagnosticViewState();
}

class _Cc1101DiagnosticViewState extends State<Cc1101DiagnosticView> {
  static const _storageKey = 'cc1101_diagnostic_samples';
  static const _riskRssiThreshold = -89.0;
  final _service = Cc1101DiagnosticService();
  final _baseUrlController = TextEditingController(text: 'http://192.168.4.1');
  final _samples = <Cc1101DiagnosticSample>[];
  StreamSubscription<Cc1101DiagnosticSample>? _subscription;
  String? _error;
  bool _isRunning = false;
  bool _useBluetooth = false;
  bool _isSopActive = false;
  bool _isSopMinimized = false;
  Cc1101DiagnosticSample? _sopSample;
  Timer? _snapshotFreezeTimer;
  DateTime? _snapshotFreezeUntil;
  Cc1101DiagnosticSample? _latestSampleDuringFreeze;
  bool _riskEpisodeHandled = false;
  DateTime? _lastSopClosedTime;
  static const _snapshotFreezeDuration = Duration(seconds: 10);
  static const _sopCooldown = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    unawaited(_loadSamples());
  }

  Cc1101DiagnosticSample? get _latest =>
      _samples.isEmpty ? null : _samples.last;

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
    try {
      if (!_useBluetooth) {
        _service.updateBaseUrl(_baseUrlController.text);
      }
      await _service.start(bluetooth: _useBluetooth);
    } catch (error) {
      await _service.stop();
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _stop() async {
    _snapshotFreezeTimer?.cancel();
    _snapshotFreezeTimer = null;
    _snapshotFreezeUntil = null;
    _latestSampleDuringFreeze = null;
    await _service.stop();
    await _subscription?.cancel();
    _subscription = null;
    if (mounted) {
      setState(() => _isRunning = false);
    }
  }

  void _addSample(Cc1101DiagnosticSample sample) {
    if (!mounted) return;
    if (_isSnapshotFrozen) {
      _latestSampleDuringFreeze = sample;
      return;
    }
    _appendSample(sample);
  }

  void _appendSample(Cc1101DiagnosticSample sample) {
    setState(() {
      _samples.add(sample);
      if (_samples.length > 200) _samples.removeAt(0);
      _error = null;
    });
    unawaited(_saveSamples());
    _checkRiskAutomatically(sample);
  }

  void _checkRiskAutomatically(Cc1101DiagnosticSample sample) {
    final rssi = sample.rssi;
    if (rssi == null || rssi <= _riskRssiThreshold) {
      _riskEpisodeHandled = false;
      return;
    }
    if (_riskEpisodeHandled) return;
    if (_isSopActive) return;
    final lastClosed = _lastSopClosedTime;
    if (lastClosed != null &&
        DateTime.now().difference(lastClosed) < _sopCooldown) {
      return;
    }

    _riskEpisodeHandled = true;
    _isSopActive = true;
    _sopSample = sample;
    _isSopMinimized = false;
    _freezeSnapshot();
    if (mounted) setState(() {});
  }

  bool get _isSnapshotFrozen {
    final until = _snapshotFreezeUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  int get _snapshotFreezeRemainingSeconds {
    final until = _snapshotFreezeUntil;
    if (until == null) return 0;
    final remaining = until.difference(DateTime.now()).inMilliseconds;
    if (remaining <= 0) return 0;
    return (remaining / 1000).ceil();
  }

  void _freezeSnapshot() {
    _snapshotFreezeTimer?.cancel();
    _snapshotFreezeUntil = DateTime.now().add(_snapshotFreezeDuration);
    _latestSampleDuringFreeze = null;
    unawaited(_pauseHardwareDetection());
    _snapshotFreezeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;
        if (!_isSnapshotFrozen) {
          _snapshotFreezeTimer?.cancel();
          _snapshotFreezeTimer = null;
          _snapshotFreezeUntil = null;
          final latestSample = _latestSampleDuringFreeze;
          _latestSampleDuringFreeze = null;
          unawaited(_resumeHardwareDetection());
          if (latestSample != null) {
            _appendSample(latestSample);
          } else {
            setState(() {});
          }
          return;
        }
        setState(() {});
      },
    );
  }

  Future<void> _pauseHardwareDetection() async {
    try {
      await _service.pauseDetection();
    } catch (error) {
      if (mounted) {
        setState(() => _error = '暫停 CC1101 偵測失敗：$error');
      }
    }
  }

  Future<void> _resumeHardwareDetection() async {
    try {
      await _service.resumeDetection();
    } catch (error) {
      if (mounted) {
        setState(() => _error = '恢復 CC1101 偵測失敗：$error');
      }
    }
  }

  Future<void> _completeSop(SopDecision decision) async {
    final sample = _sopSample;
    if (!_isSopActive || sample == null) return;

    _isSopActive = false;
    _sopSample = null;
    _lastSopClosedTime = DateTime.now();
    if (mounted) setState(() {});

    final persisted = await _persistSopDecision(sample, decision);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          persisted
              ? decision == SopDecision.confirmedDanger
                  ? '複檢異常：已記錄紅色高風險事件'
                  : '複檢正常：已記錄黃色待驗證事件'
              : '定位服務不可用，無法寫入事件紀錄',
        ),
        backgroundColor: persisted
            ? decision == SopDecision.confirmedDanger
                ? Colors.red
                : Colors.amber.shade800
            : Colors.orange,
      ),
    );
  }

  Future<bool> _persistSopDecision(
    Cc1101DiagnosticSample sample,
    SopDecision decision,
  ) async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    final position = await Geolocator.getCurrentPosition();
    final isDanger = decision == SopDecision.confirmedDanger;
    await DatabaseHelper.instance.insertRecord(
      DetectionRecord(
        timestamp: DateTime.now().toUtc(),
        maxDeltaT: 0,
        maxRSSI: sample.rssi ?? 0,
        latitude: position.latitude,
        longitude: position.longitude,
        statusColor: isDanger ? 'RED' : 'YELLOW',
        userDecision: isDanger ? 'CONFIRMED_DANGER' : 'UNCERTAIN_WARNING',
        adviceText: isDanger
            ? '複檢異常：請立即檢查該位置並依現場安全程序處置。'
            : '複檢正常（疑似誤判）：建議貼膠帶遮蔽可疑位置或拔除電源後再驗證。',
      ),
    );
    return true;
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
    _snapshotFreezeTimer?.cancel();
    _service.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sample = _latest;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 180),
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
                              '此頁會自動收集無線訊號資料；RSSI 高於 -89 dBm 時會自動觸發高風險 SOP。'),
                          const SizedBox(height: 16),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment<bool>(
                                value: false,
                                label: Text('Wi-Fi / HTTP'),
                                icon: Icon(Icons.wifi),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                label: Text('Bluetooth BLE'),
                                icon: Icon(Icons.bluetooth),
                              ),
                            ],
                            selected: {_useBluetooth},
                            onSelectionChanged: _isRunning
                                ? null
                                : (selection) {
                                    setState(
                                        () => _useBluetooth = selection.first);
                                  },
                          ),
                          const SizedBox(height: 8),
                          if (!_useBluetooth)
                            TextField(
                              controller: _baseUrlController,
                              enabled: !_isRunning,
                              keyboardType: TextInputType.url,
                              decoration: const InputDecoration(
                                labelText: 'ESP32 Wi-Fi 位址',
                                hintText: '例如 http://192.168.4.1',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          if (!_useBluetooth) const SizedBox(height: 8),
                          Text(
                            _useBluetooth
                                ? '將搜尋 $_bluetoothDeviceName 並接收 BLE JSON 通知'
                                : '每 500 ms 讀取 ${_baseUrlController.text.trim()}/data',
                          ),
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
                                onPressed:
                                    _samples.isEmpty ? null : _copySamples,
                                icon: const Icon(Icons.copy),
                                label: const Text('複製 JSON'),
                              ),
                              TextButton.icon(
                                onPressed:
                                    _samples.isEmpty ? null : _clearSamples,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('清除紀錄'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(_isRunning ? '測試中，每 500 ms 讀取一次' : '測試尚未開始'),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
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
        ),
        if (_isSopActive && _sopSample != null)
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: SopCard(
                    deltaT: null,
                    rssi: _sopSample!.rssi ?? 0,
                    description: 'CC1101 偵測到高風險訊號，請完成現場光學複檢。',
                    snapshotFrozen: _isSnapshotFrozen,
                    freezeRemainingSeconds: _snapshotFreezeRemainingSeconds,
                    minimized: _isSopMinimized,
                    onToggleMinimized: () {
                      setState(() => _isSopMinimized = !_isSopMinimized);
                    },
                    onDecision: _completeSop,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String get _bluetoothDeviceName =>
      Cc1101DiagnosticService.defaultBluetoothDeviceName;
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

String _format(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
}
