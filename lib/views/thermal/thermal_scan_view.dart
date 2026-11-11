import 'package:flutter/material.dart';

import '../../models/scan_data.dart';
import '../../services/hardware_connection_service.dart';
import '../../utils/thermal_interpolator.dart';
import 'thermal_heatmap64_view.dart';

class ThermalScanView extends StatelessWidget {
  const ThermalScanView({super.key});

  @override
  Widget build(BuildContext context) {
    final service = HardwareConnectionScope.of(context);
    final scan = service.latestScan;
    final result = scan?.analyze();
    final activeConnection = service.activeConnection;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConnectionSummary(
                service: service,
                activeConnection: activeConnection,
              ),
              const SizedBox(height: 12),
              if (result == null)
                const Card(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Center(child: Text('尚未收到掃描資料')),
                  ),
                )
              else ...[
                _StatusCard(
                  level: result.level.label,
                  color: switch (result.level) {
                    DetectionLevel.safe => Colors.green,
                    DetectionLevel.warning => Colors.orange,
                    DetectionLevel.highRisk => Colors.red,
                  },
                  deviceName: scan!.deviceName,
                ),
                const SizedBox(height: 12),
                ThermalHeatmap64View(
                  temperatures: _interpolate(scan),
                  minTemp: 20,
                  maxTemp: 40,
                  warningThreshold: 35,
                ),
                const SizedBox(height: 12),
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
              ],
              const SizedBox(height: 12),
              const Text(
                'CC1101_BLE 連線請由「硬體監控」頁面操作；此頁顯示共用熱成像資料。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<List<double>> _interpolate(ScanData scan) {
    const size = ThermalHeatmap64View.gridSize;
    final values = ThermalInterpolator.interpolate8x8(
      scan.thermalGrid,
      targetSize: size,
    );
    return List<List<double>>.generate(
      size,
      (row) => List<double>.generate(
        size,
        (column) => values[row * size + column],
        growable: false,
      ),
      growable: false,
    );
  }
}

class _ConnectionSummary extends StatelessWidget {
  const _ConnectionSummary({
    required this.service,
    required this.activeConnection,
  });

  final HardwareConnectionService service;
  final HardwareConnectionType? activeConnection;

  @override
  Widget build(BuildContext context) {
    final failedConnection = service.failedConnection;
    final status = activeConnection != null
        ? _statusLabel(service.stateFor(activeConnection!).status)
        : service.isSimulating
            ? '模擬掃描中'
            : failedConnection == null
                ? 'Disconnected'
                : '${_connectionName(failedConnection)} · Error: ${service.stateFor(failedConnection).error}';

    return Card(
      child: ListTile(
        leading: const Icon(Icons.sync),
        title: const Text('共用連線狀態'),
        subtitle: Text(
          activeConnection == null
              ? status
              : '${_connectionName(activeConnection!)} · $status',
        ),
      ),
    );
  }

  String _statusLabel(HardwareConnectionStatus status) => switch (status) {
        HardwareConnectionStatus.disconnected => 'Disconnected',
        HardwareConnectionStatus.connecting => 'Connecting',
        HardwareConnectionStatus.connected => 'Connected',
        HardwareConnectionStatus.error => 'Error',
      };

  String _connectionName(HardwareConnectionType type) => switch (type) {
          HardwareConnectionType.esp32Bluetooth => 'CC1101_BLE',
      };
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
