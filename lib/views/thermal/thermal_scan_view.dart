import 'package:flutter/material.dart';

import '../../models/scan_data.dart';
import '../../services/thermal_simulator.dart';
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
  bool _isScanning = true;
  String? _alertScanId;

  @override
  void initState() {
    super.initState();
    _runScan();
  }

  void _runScan() {
    // 模擬器同步產生一筆新資料；真實硬體接入時可替換此服務實作。
    setState(() {
      _isScanning = true;
      _scan = _simulator.scan();
    });

    final scan = _scan!;
    setState(() => _isScanning = false);
    // 每筆掃描只提示一次，避免畫面重建時重複彈窗。
    if (scan.analyze().isHighRisk && _alertScanId != scan.id) {
      _alertScanId = scan.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) SopDialog.show(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    if (_isScanning || scan == null) {
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
                      child: _ThermalGrid(thermalGrid: scan.thermalGrid),
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
                    onPressed: _runScan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新掃描隨機熱點'),
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

class _ThermalGrid extends StatelessWidget {
  const _ThermalGrid({required this.thermalGrid});

  static const minimumTemperature = 20.0;
  static const maximumTemperature = 35.0;
  final List<double> thermalGrid;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 64,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemBuilder: (context, index) {
          final temperature = thermalGrid[index];
          return Semantics(
            label: '第 ${index + 1} 格，${temperature.toStringAsFixed(1)} 度',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _colorFor(temperature),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        },
      ),
    );
  }

  static Color _colorFor(double temperature) {
    // 使用固定絕對溫度範圍，避免低溫資料因相對正規化而誤呈紅色。
    final value = temperature
        .clamp(minimumTemperature, maximumTemperature)
        .toDouble();
    if (value <= 26) {
      return Color.lerp(Colors.blueGrey.shade800, Colors.lightBlue, (value - 20) / 6)!;
    }
    if (value <= 28.5) {
      return Color.lerp(Colors.lightBlue, Colors.orange, (value - 26) / 2.5)!;
    }
    return Color.lerp(Colors.orange, Colors.red, (value - 28.5) / 6.5)!;
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