import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/cc1101_diagnostic_sample.dart';
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

  List<List<double>> _interpolatedThermalGrid(List<double> thermalGrid) {
    final values = ThermalInterpolator.interpolate8x8(
      thermalGrid,
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
    final thermalGrid = scan?.thermalGrid ?? cc1101Sample?.thermalPixels;
    final activeConnection = service.activeConnection;
    final isScanning = service.isScanning;
    final isEsp32Connected =
        activeConnection == HardwareConnectionType.esp32Bluetooth &&
            service.stateFor(HardwareConnectionType.esp32Bluetooth).status ==
                HardwareConnectionStatus.connected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConnectionCard(
                title: 'CC1101_BLE',
                icon: Icons.bluetooth,
                state: service.stateFor(
                  HardwareConnectionType.esp32Bluetooth,
                ),
                canConnect: service.canConnect,
                onConnect: () => _connect(
                  HardwareConnectionType.esp32Bluetooth,
                ),
                onDisconnect:
                    service.isSimulating ? service.stopSimulation : _disconnect,
                isActive:
                    activeConnection == HardwareConnectionType.esp32Bluetooth,
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
              if (thermalGrid == null)
                const _EmptyThermalCard()
              else
                ThermalHeatmap64View(
                  temperatures: _interpolatedThermalGrid(thermalGrid),
                  minTemp: 20,
                  maxTemp: 40,
                  warningThreshold: 35,
                ),
              if (thermalGrid == null && isEsp32Connected) ...[
                const SizedBox(height: 8),
                const Text(
                  '目前韌體只傳送 CC1101 診斷資料，尚未傳送 64 格熱像資料；'
                  '熱圖與溫差風險判定需由韌體另外提供熱像資料。',
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 12),
              _DetectionStatusCard(result: scan?.analyze()),
              const SizedBox(height: 12),
              if (isScanning) ...[
                const SizedBox(height: 8),
                Text(
                  service.isSimulating ? '模擬模式 · 未連接硬體' : 'CC1101_BLE 即時資料',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SignalCard(
                      icon: Icons.bluetooth,
                      label: 'ESP32 BLE RSSI',
                      value: service.supportsBleRssi
                          ? _formatRssi(service.esp32Rssi?.toDouble())
                          : '此平台不支援',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SignalCard(
                      icon: Icons.sensors_outlined,
                      label: '熱像 RSSI',
                      value: _formatRssi(scan?.rssi),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SignalCard(
                icon: Icons.wifi_tethering_outlined,
                label: 'CC1101 RSSI',
                value: _formatRssi(cc1101Sample?.rssi),
              ),
              if (service.esp32RssiError != null) ...[
                const SizedBox(height: 4),
                Text(
                  'ESP32 BLE RSSI 讀取失敗：${service.esp32RssiError}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              _SensorDataCard(
                sample: cc1101Sample,
                isSimulating: service.isSimulating,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _connectionName(HardwareConnectionType type) => switch (type) {
      HardwareConnectionType.esp32Bluetooth => 'CC1101_BLE',
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

class _SensorDataCard extends StatelessWidget {
  const _SensorDataCard({
    required this.sample,
    required this.isSimulating,
  });

  final Cc1101DiagnosticSample? sample;
  final bool isSimulating;

  @override
  Widget build(BuildContext context) {
    final thermalPixels = sample?.thermalPixels;
    final thermalSummary = thermalPixels == null
        ? '韌體尚未透過 BLE 上報'
        : _thermalSummary(thermalPixels);
    final irStatus = switch (sample?.irDetected) {
      true => '偵測到紅外線${_irDetails(sample!)}',
      false => '目前未偵測到紅外線${_irDetails(sample!)}',
      null => '韌體尚未透過 BLE 上報',
    };
    final cc1101Status = sample == null
        ? '等待 BLE 診斷資料'
        : '${isSimulating ? '模擬資料 · ' : ''}'
            'RSSI ${_formatRssi(sample!.rssi)} · LQI ${sample!.lqi?.toStringAsFixed(0) ?? '--'} · '
            'CRC ${_formatCrc(sample!.crcOk)} · PER ${_formatPercent(sample!.per)} · '
            '封包 ${sample!.receivedPackets ?? '--'} 收 / ${sample!.lostPackets ?? '--'} 失';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('感測器資料', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _SensorStatusRow(
              icon: Icons.device_thermostat,
              title: 'AMG8833 熱像',
              value: thermalSummary,
              isAvailable: thermalPixels != null,
            ),
            const Divider(height: 20),
            _SensorStatusRow(
              icon: Icons.sensors,
              title: 'CC1101 射頻',
              value: cc1101Status,
              isAvailable: sample != null && !isSimulating,
            ),
            const Divider(height: 20),
            _SensorStatusRow(
              icon: Icons.wb_incandescent_outlined,
              title: 'VS1838B 紅外線',
              value: irStatus,
              isAvailable: sample?.irDetected != null,
            ),
          ],
        ),
      ),
    );
  }

  String _irDetails(Cc1101DiagnosticSample value) {
    final parts = [
      if (value.irProtocol != null) '協定 ${value.irProtocol}',
      if (value.irAddress != null) '位址 ${value.irAddress}',
      if (value.irCommand != null) '指令 ${value.irCommand}',
    ];
    return parts.isEmpty ? '' : '（${parts.join(' · ')}）';
  }

  String _thermalSummary(List<double> values) {
    final minimum = values.reduce(math.min);
    final maximum = values.reduce(math.max);
    return '64 格 · ${minimum.toStringAsFixed(1)}–'
        '${maximum.toStringAsFixed(1)} °C · ΔT ${(maximum - minimum).toStringAsFixed(1)} °C';
  }
}

class _SensorStatusRow extends StatelessWidget {
  const _SensorStatusRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.isAvailable,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final color = isAvailable
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatRssi(double? value) =>
    value == null ? '-- dBm' : '${value.toStringAsFixed(1)} dBm';

String _formatCrc(bool? value) =>
    value == null ? '--' : (value ? 'OK' : 'FAIL');

String _formatPercent(double? value) =>
    value == null ? '--' : '${(value * 100).toStringAsFixed(2)}%';
