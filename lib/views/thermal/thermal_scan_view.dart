import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/scan_data.dart';
import '../../services/thermal_simulator.dart';
import '../../utils/thermal_interpolator.dart';
import 'dynamic_thermal_painter.dart';
import 'sop_dialog.dart';

// 熱成像子模組：負責產生掃描、顯示熱圖與呈現風險結果。
class ThermalScanView extends StatefulWidget {
  const ThermalScanView({super.key});

  @override
  State<ThermalScanView> createState() => _ThermalScanViewState();
}

class _ThermalScanViewState extends State<ThermalScanView> {
  static const _simulator = ThermalSimulator();
  ScanData? _scan;
  List<double>? _interpolatedGrid;
  bool _isScanning = true;
  Timer? _streamTimer;
  String? _alertScanId;

  @override
  void initState() {
    super.initState();
    _startStream();
    _runScan();
  }

  void _runScan() {
    // 模擬器同步產生一筆新資料；真實硬體接入時可替換此服務實作。
    _updateScan(_simulator.scan());
  }

  void _startStream() {
    if (_streamTimer != null) return;

    setState(() => _isScanning = true);
    _streamTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _updateScan(_simulator.scan()),
    );
  }

  void _pauseStream() {
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
      _pauseStream();
      _alertScanId = scan.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) SopDialog.show(context);
      });
    }
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _streamTimer = null;
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