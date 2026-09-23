import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/detection_record.dart';
import '../../models/scan_data.dart';
import '../../services/database_helper.dart';
import '../../services/thermocam_ble_service.dart';
import '../../services/thermal_simulator.dart';
import '../../utils/thermal_interpolator.dart';
import 'dynamic_thermal_painter.dart';
import 'sop_dialog.dart';

// 熱成像子模組：負責產生掃描、顯示熱圖與呈現風險結果。
class ThermalScanView extends StatefulWidget {
  const ThermalScanView({super.key});

  @override
  State<ThermalScanView> createState() => ThermalScanViewState();
}

class ThermalScanViewState extends State<ThermalScanView> {
  static const _simulator = ThermalSimulator();
  final _bleService = ThermoCamBleService();
  ScanData? _scan;
  List<double>? _interpolatedGrid;
  bool _isScanning = true;
  Timer? _streamTimer;
  StreamSubscription<ScanData>? _bleSubscription;
  String? _alertScanId;
  String _connectionStatus = '尚未連接硬體，現在顯示模擬資料';
  bool _usingHardware = false;
  bool _isConnecting = false;
  final Set<String> _persistedRiskScanIds = {};

  @override
  void initState() {
    super.initState();
    _startSimulatorStream();
  }

  Future<void> connectHardware() async {
    if (_isConnecting || _usingHardware) return;

    _streamTimer?.cancel();
    _streamTimer = null;
    setState(() {
      _isConnecting = true;
      _connectionStatus = '請在瀏覽器視窗中選擇 ThermoCam_BLE...';
    });

    try {
      await _bleService.connect();
      _bleSubscription = _bleService.scans.listen(_updateScan);
      if (mounted) {
        setState(() {
          _usingHardware = true;
          _isScanning = true;
          _isConnecting = false;
          _connectionStatus = '已連線 ThermoCam_BLE';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _connectionStatus = '硬體未連線，使用模擬資料';
      });
      _startSimulatorStream();
    }
  }

  void _startStream() {
    if (_usingHardware) return;
    _startSimulatorStream();
  }

  void _startSimulatorStream() {
    if (_streamTimer != null) return;

    setState(() => _isScanning = true);
    _streamTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _updateScan(_simulator.scan()),
    );
  }

  void _pauseStream() {
    if (_usingHardware) {
      setState(() => _isScanning = false);
      return;
    }
    _streamTimer?.cancel();
    _streamTimer = null;
    if (mounted) setState(() => _isScanning = false);
  }

  void _updateScan(ScanData scan) {
    final interpolatedGrid = ThermalInterpolator.interpolate8x8(
      scan.thermalGrid,
      targetSize: 64,
    );

    if (!mounted) return;
    setState(() {
      _scan = scan;
      _interpolatedGrid = interpolatedGrid;
    });

    // 每筆掃描只提示一次，避免畫面重建時重複彈窗。
    if (scan.analyze().isHighRisk && _alertScanId != scan.id) {
      unawaited(_persistHighRiskScan(scan));
      _pauseStream();
      _alertScanId = scan.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) SopDialog.show(context);
      });
    }
  }

  Future<void> _persistHighRiskScan(ScanData scan) async {
    if (_persistedRiskScanIds.contains(scan.id)) return;

    final position = await _getCurrentPosition();
    if (position == null) return;

    final result = scan.analyze();
    await DatabaseHelper.instance.insertRecord(
      DetectionRecord(
        timestamp: DateTime.now().toUtc(),
        maxDeltaT: result.deltaT,
        maxRSSI: result.rssi,
        latitude: position.latitude,
        longitude: position.longitude,
        statusColor: 'RED',
        userDecision: 'CONFIRMED_DANGER',
        adviceText: '請立即檢查該位置並依現場安全程序處置。',
      ),
    );
    _persistedRiskScanIds.add(scan.id);
  }

  Future<Position?> _getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition();
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _streamTimer = null;
    _bleSubscription?.cancel();
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    final interpolatedGrid = _interpolatedGrid;
    if (scan == null || interpolatedGrid == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final result = scan.analyze();
    final levelColor = switch (result.level) {
      DetectionLevel.safe => Colors.green,
      DetectionLevel.warning => Colors.orange,
      DetectionLevel.highRisk => Colors.red,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusCard(
                    level: result.level.label,
                    color: levelColor,
                    deviceName: scan.deviceName,
                  ),
                  const SizedBox(height: 8),
                  Text(_connectionStatus),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _isConnecting || _usingHardware
                        ? null
                        : connectHardware,
                    icon: _isConnecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bluetooth),
                    label: Text(
                      _isConnecting
                          ? '等待硬體選擇...'
                          : _usingHardware
                              ? '硬體已連線'
                              : '連接 ThermoCam 硬體',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: CustomPaint(
                          painter: DynamicThermalPainter(
                            grid64x64: interpolatedGrid,
                            minTemp: result.minimumTemperature,
                            maxTemp: result.maximumTemperature,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 32,
                        runSpacing: 16,
                        children: [
                          _Metric(
                            label: '溫差 ΔT',
                            value: '${result.deltaT.toStringAsFixed(1)} °C',
                          ),
                          _Metric(
                            label: 'RSSI',
                            value: '${result.rssi.toStringAsFixed(1)} dBm',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isScanning ? _pauseStream : _startStream,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      _isScanning ? '暫停即時掃描' : '開始即時掃描',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.level,
    required this.color,
    required this.deviceName,
  });

  final String level;
  final Color color;
  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('目前判定', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              level,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(deviceName),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}