import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/detection_record.dart';
import '../../models/scan_data.dart';
import '../../services/database_helper.dart';
import '../../services/hardware_connection_service.dart';
import '../../utils/thermal_interpolator.dart';
import '../thermal/sop_dialog.dart';
import '../thermal/thermal_heatmap64_view.dart';

class HardwareMonitorView extends StatefulWidget {
  const HardwareMonitorView({super.key});

  @override
  State<HardwareMonitorView> createState() => _HardwareMonitorViewState();
}

class _HardwareMonitorViewState extends State<HardwareMonitorView> {
  HardwareConnectionService? _service;
  StreamSubscription<ScanData>? _riskSubscription;
  bool _isSopOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = HardwareConnectionScope.of(context);
    if (identical(service, _service)) return;
    _riskSubscription?.cancel();
    _service = service;
    _riskSubscription = service.riskEvents.listen(_showSopForScan);
  }

  void _showSopForScan(ScanData scan) {
    if (_isSopOpen) return;
    _isSopOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _isSopOpen = false;
        return;
      }
      try {
        final decision = await SopDialog.show(context);
        if (decision != null) await _persistSopDecision(scan, decision);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('處理 SOP 結果失敗：$error')),
          );
        }
      } finally {
        _isSopOpen = false;
      }
    });
  }

  Future<void> _persistSopDecision(
    ScanData scan,
    SopDecision decision,
  ) async {
    final position = await _getCurrentPosition();
    if (!mounted) return;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('定位服務不可用，無法寫入事件紀錄')),
      );
      return;
    }

    final result = scan.analyze();
    final isDanger = decision == SopDecision.confirmedDanger;
    await DatabaseHelper.instance.insertRecord(
      DetectionRecord(
        timestamp: DateTime.now().toUtc(),
        maxDeltaT: result.deltaT,
        maxRSSI: result.rssi,
        latitude: position.latitude,
        longitude: position.longitude,
        statusColor: isDanger ? 'RED' : 'YELLOW',
        userDecision: isDanger ? 'CONFIRMED_DANGER' : 'UNCERTAIN_WARNING',
        adviceText: isDanger
            ? '複檢異常：請立即檢查該位置並依現場安全程序處置。'
            : '複檢正常（疑似誤判）：建議貼膠帶遮蔽可疑位置或拔除電源後再驗證。',
      ),
    );
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

  Future<void> _connect(HardwareConnectionType type) async {
    try {
      await _service!.connect(
        type,
        fallbackToSimulator: true,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('連線失敗：$error')),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    try {
      await _service!.disconnect();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('中斷連線失敗：$error')),
        );
      }
    }
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
  void dispose() {
    _riskSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = HardwareConnectionScope.of(context);
    final scan = service.latestScan;
    final cc1101Sample = service.latestCc1101Sample;
    final activeConnection = service.activeConnection;
    final isScanning = service.isScanning;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConnectionCard(
                title: 'ThermoCam_BLE',
                icon: Icons.bluetooth,
                state: service.stateFor(
                  HardwareConnectionType.thermocamBluetooth,
                ),
                canConnect: service.canConnect,
                onConnect: () => _connect(
                  HardwareConnectionType.thermocamBluetooth,
                ),
                onDisconnect:
                    service.isSimulating ? service.stopSimulation : _disconnect,
                isActive: activeConnection ==
                    HardwareConnectionType.thermocamBluetooth,
                isSimulating: service.isSimulating,
              ),
              for (final type in HardwareConnectionType.values)
                if (service.stateFor(type).error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_connectionName(type)}：${service.stateFor(type).error}',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              const SizedBox(height: 12),
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
              if (isScanning) ...[
                const SizedBox(height: 8),
                Text(
                  service.isSimulating ? '模擬模式 · 未連接硬體' : 'ThermoCam_BLE 即時資料',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SignalCard(
                      icon: Icons.sensors_outlined,
                      label: 'ThermoCam RSSI',
                      value: _formatRssi(scan?.rssi),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SignalCard(
                      icon: Icons.wifi_tethering_outlined,
                      label: 'CC1101 RSSI',
                      value: _formatRssi(cc1101Sample?.rssi),
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

String _connectionName(HardwareConnectionType type) => switch (type) {
      HardwareConnectionType.thermocamBluetooth => 'ThermoCam_BLE',
    };

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.title,
    required this.icon,
    required this.state,
    required this.canConnect,
    required this.onConnect,
    required this.onDisconnect,
    required this.isActive,
    required this.isSimulating,
  });

  final String title;
  final IconData icon;
  final HardwareConnectionState state;
  final bool canConnect;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final bool isActive;
  final bool isSimulating;

  @override
  Widget build(BuildContext context) {
    final isConnecting = state.status == HardwareConnectionStatus.connecting;
    final isConnected =
        isActive && state.status == HardwareConnectionStatus.connected;
    final status = isSimulating
        ? '模擬掃描中'
        : switch (state.status) {
            HardwareConnectionStatus.disconnected => 'Disconnected',
            HardwareConnectionStatus.connecting => 'Connecting',
            HardwareConnectionStatus.connected => 'Connected',
            HardwareConnectionStatus.error => 'Error',
          };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    Text(status),
                  ],
                ),
              ],
            ),
            isConnected || isSimulating
                ? OutlinedButton.icon(
                    onPressed: onDisconnect,
                    icon: const Icon(Icons.link_off),
                    label: Text(isSimulating ? '停止模擬' : '斷線'),
                  )
                : FilledButton.icon(
                    onPressed: canConnect && !isConnecting ? onConnect : null,
                    icon: isConnecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(icon),
                    label: Text(isConnecting ? '連線中...' : '連線'),
                  ),
          ],
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
