import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/cc1101_diagnostic_sample.dart';
import '../../models/scan_data.dart';
import '../../services/esp32_http_service.dart';
import '../../services/hardware_data_monitor.dart';
import '../../services/thermal_simulator.dart';
import '../../utils/thermal_interpolator.dart';
import '../thermal/thermal_heatmap64_view.dart';

class HardwareMonitorView extends StatefulWidget {
  const HardwareMonitorView({super.key});

  @override
  State<HardwareMonitorView> createState() => _HardwareMonitorViewState();
}

class _HardwareMonitorViewState extends State<HardwareMonitorView> {
  static const _simulator = ThermalSimulator();
  final _esp32Service = Esp32HttpService();
  final _random = Random();
  StreamSubscription<HardwareDataEvent>? _subscription;
  StreamSubscription<ScanData>? _scanSubscription;
  Timer? _simulationTimer;
  ScanData? _latestScan;
  double? _cc1101Rssi;
  bool _isConnecting = false;
  bool _isScanning = false;
  bool _isSimulating = false;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _subscription = HardwareDataMonitor.instance.events.listen(_onData);
  }

  void _onData(HardwareDataEvent event) {
    if (!mounted) return;
    if (event.scan == null && event.cc1101Sample == null) return;
    setState(() {
      if (event.scan != null) _latestScan = event.scan;
      final sample = event.cc1101Sample;
      if (sample != null) _cc1101Rssi = sample.rssi;
    });
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _subscription?.cancel();
    _scanSubscription?.cancel();
    unawaited(_esp32Service.dispose());
    super.dispose();
  }

  Future<void> _toggleScan() async {
    if (_isConnecting) return;
    if (_isScanning) {
      _simulationTimer?.cancel();
      _simulationTimer = null;
      await _esp32Service.stop();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (mounted) {
        setState(() {
          _isScanning = false;
          _isSimulating = false;
        });
      }
      return;
    }

    setState(() {
      _isConnecting = true;
      _isSimulating = false;
    });
    _scanSubscription = _esp32Service.scans.listen(
      (_) {},
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _connectionError = error.toString());
        unawaited(_startSimulator());
      },
    );
    try {
      await _esp32Service.start();
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _isScanning = true;
        _isSimulating = false;
        _connectionError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _connectionError = error.toString());
      }
      await _startSimulator();
    }
  }

  Future<void> _startSimulator() async {
    if (_isSimulating || !mounted) return;
    await _esp32Service.stop();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (!mounted) return;
    setState(() {
      _isConnecting = false;
      _isScanning = true;
      _isSimulating = true;
    });
    _simulationTimer ??= Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _publishSimulatedData(),
    );
    _publishSimulatedData();
  }

  void _publishSimulatedData() {
    final scan = _simulator.scan();
    HardwareDataMonitor.instance.add(
      source: '熱成像模擬資料',
      rawText: jsonEncode({
        'device_name': scan.deviceName,
        'rssi': scan.rssi,
        'thermal_grid': scan.thermalGrid,
        'captured_at': scan.capturedAt,
      }),
      scan: scan,
    );
    final cc1101Rssi = -90 + _random.nextDouble() * 45;
    final sample = Cc1101DiagnosticSample(
      capturedAt: DateTime.now(),
      rssi: cc1101Rssi,
      lqi: null,
      crcOk: null,
      receivedPackets: null,
      lostPackets: null,
      per: null,
      distanceMeters: null,
      rawJson: {'rssi': cc1101Rssi, 'simulated': true},
    );
    HardwareDataMonitor.instance.add(
      source: 'CC1101 模擬資料',
      rawText: sample.toJsonLine(),
      cc1101Sample: sample,
    );
  }

  List<List<double>> _interpolatedThermalGrid(ScanData scan) {
    final values = ThermalInterpolator.interpolate8x8(
      scan.thermalGrid,
      targetSize: ThermalHeatmap64View.gridSize,
    );
    return List<List<double>>.generate(
      ThermalHeatmap64View.gridSize,
      (row) => List<double>.generate(
        ThermalHeatmap64View.gridSize,
        (column) => values[row * ThermalHeatmap64View.gridSize + column],
        growable: false,
      ),
      growable: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = _latestScan;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (scan == null)
                const _EmptyThermalCard()
              else
                ThermalHeatmap64View(
                  temperatures: _interpolatedThermalGrid(scan),
                  minTemp: 20,
                  maxTemp: 40,
                  warningThreshold: 35,
                ),
              const SizedBox(height: 12),
              _DetectionStatusCard(result: scan?.analyze()),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isConnecting ? null : _toggleScan,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_isScanning ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _isConnecting
                      ? '連線中...'
                      : _isScanning
                          ? '停止掃描'
                          : '開始掃描',
                ),
              ),
              if (_isScanning) ...[
                const SizedBox(height: 8),
                Text(
                  _isSimulating ? '模擬模式 · 未連接硬體' : 'ESP32 即時資料',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                if (_isSimulating && _connectionError != null) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        kIsWeb
                            ? 'Web 連線失敗：請讓電腦連上 AntiPinhole-ESP32，並從 HTTP 網址開啟 App；若 App 使用 HTTPS，瀏覽器可能禁止連線到 http://192.168.4.1/data。\n${_connectionError!}'
                            : '無法連線 http://192.168.4.1/data：請確認手機已連上 AntiPinhole-ESP32。\n${_connectionError!}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SignalCard(
                      icon: Icons.sensors_outlined,
                      label: 'ESP32 RSSI',
                      value: _formatRssi(scan?.rssi),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SignalCard(
                      icon: Icons.wifi_tethering_outlined,
                      label: 'CC1101 RSSI',
                      value: _formatRssi(_cc1101Rssi),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectionStatusCard extends StatelessWidget {
  const _DetectionStatusCard({required this.result});

  final ScanResult? result;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (result?.level) {
      DetectionLevel.safe => ('安全', Colors.green),
      DetectionLevel.warning => ('警示', Colors.orange),
      DetectionLevel.highRisk => ('高風險', Colors.red),
      null => ('等待資料', Theme.of(context).colorScheme.outline),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, color: color),
            const SizedBox(width: 12),
            Text('目前判定', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyThermalCard extends StatelessWidget {
  const _EmptyThermalCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: AspectRatio(
        aspectRatio: 1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.thermostat_auto_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 8),
            const Text('等待熱成像資料'),
          ],
        ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRssi(double? value) =>
    value == null ? '-- dBm' : '${value.toStringAsFixed(1)} dBm';
