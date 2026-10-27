import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/detection_record.dart';
import '../../models/scan_data.dart';
import '../../services/database_helper.dart';
import '../../services/esp32_http_service.dart';
import '../../services/thermocam_ble_service.dart';
import '../../services/thermal_simulator.dart';
import '../../utils/thermal_interpolator.dart';
import 'thermal_heatmap64_view.dart';
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
  final _esp32Service = Esp32HttpService();
  ScanData? _scan;
  List<List<double>>? _grid64x64;
  bool _isScanning = false;
  Timer? _streamTimer;
  StreamSubscription<ScanData>? _bleSubscription;
  StreamSubscription<ScanData>? _esp32Subscription;
  String _connectionStatus = '尚未連接硬體，按「開始即時掃描」可使用模擬資料';
  bool _usingHardware = false;
  bool _usingEsp32 = false;
  bool _isConnecting = false;
  // 頁面內鎖定：避免同一頁在 post-frame callback 排隊期間重複開啟 SOP。
  bool _isSopActive = false;
  bool _isSopMinimized = false;
  ScanData? _sopScan;
  Timer? _snapshotFreezeTimer;
  DateTime? _snapshotFreezeUntil;
  ScanData? _latestScanDuringFreeze;
  // 同一段連續高風險只處理一次，必須先恢復安全才重新觸發。
  bool _riskEpisodeHandled = false;
  // 使用者完成本次判定後，保留冷卻時間避免立即被下一個異常打斷。
  DateTime? _lastSopClosedTime;
  static const _snapshotFreezeDuration = Duration(seconds: 10);
  static const _sopCooldown = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
  }

  Future<void> connectHardware() async {
    if (_isConnecting || _usingHardware || _usingEsp32) return;

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
        _connectionStatus = '藍牙連線失敗：$error，按「開始即時掃描」使用模擬資料';
      });
    }
  }

  Future<void> connectEsp32() async {
    if (_isConnecting || _usingHardware || _usingEsp32) return;

    _streamTimer?.cancel();
    _streamTimer = null;
    setState(() {
      _isConnecting = true;
      _connectionStatus = '正在連線 ESP32：172.20.10.3...';
    });

    _usingEsp32 = true;
    _esp32Subscription = _esp32Service.scans.listen(
      _updateScan,
      onError: (Object error) {
        if (mounted) setState(() => _connectionStatus = 'ESP32 讀取失敗：$error');
      },
    );
    try {
      await _esp32Service.start();
      if (mounted) {
        setState(() {
          _isScanning = true;
          _isConnecting = false;
          _connectionStatus = '已連線 ESP32 Wi-Fi';
        });
      }
    } catch (error) {
      _usingEsp32 = false;
      await _esp32Subscription?.cancel();
      _esp32Subscription = null;
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _connectionStatus = 'ESP32 連線失敗：$error，按「開始即時掃描」使用模擬資料';
      });
    }
  }

  void _startStream() {
    if (_usingHardware) return;
    if (_usingEsp32) {
      unawaited(_esp32Service.start());
      if (mounted) setState(() => _isScanning = true);
      return;
    }
    _startSimulatorStream();
  }

  void _startSimulatorStream() {
    if (_streamTimer != null) return;

    setState(() => _isScanning = true);
    // 模擬器以接近硬體的頻率產生資料，沿用相同的更新與風險判定流程。
    _streamTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _updateScan(_simulator.scan()),
    );
  }

  void _pauseStream() {
    if (_usingHardware || _usingEsp32) {
      if (_usingEsp32) unawaited(_esp32Service.stop());
      setState(() => _isScanning = false);
      return;
    }
    _streamTimer?.cancel();
    _streamTimer = null;
    if (mounted) setState(() => _isScanning = false);
  }

  void _updateScan(ScanData scan) {
    if (_isSnapshotFrozen) {
      // 保留最新資料，讓凍結結束後立即恢復到最新狀態；畫面維持觸發當下快照。
      _latestScanDuringFreeze = scan;
      return;
    }

    // 正常狀態更新熱圖與目前數值；凍結期間的資料由上方暫存。
    final interpolatedGrid = ThermalInterpolator.interpolate8x8(
      scan.thermalGrid,
      targetSize: 64,
    );

    if (!mounted) return;
    setState(() {
      _scan = scan;
      _grid64x64 = List<List<double>>.generate(
        64,
        (row) => List<double>.generate(
          64,
          (column) => interpolatedGrid[row * 64 + column],
          growable: false,
        ),
        growable: false,
      );
    });

    final isHighRisk = scan.analyze().isHighRisk;
    if (!isHighRisk) {
      // 只有風險解除後才重新 armed，避免冷卻期結束後持續重複彈窗。
      _riskEpisodeHandled = false;
    }
    if (isHighRisk && !_riskEpisodeHandled) {
      _riskEpisodeHandled = true;
      _showSopForScan(scan);
    }
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
    _latestScanDuringFreeze = null;
    _snapshotFreezeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;
        if (!_isSnapshotFrozen) {
          _snapshotFreezeTimer?.cancel();
          _snapshotFreezeTimer = null;
          _snapshotFreezeUntil = null;
          final latestScan = _latestScanDuringFreeze;
          _latestScanDuringFreeze = null;
          setState(() {});
          if (latestScan != null) _updateScan(latestScan);
          return;
        }
        setState(() {});
      },
    );
  }

  void _showSopForScan(ScanData scan) {
    // _isSopActive 防止本頁重入；硬體連線保留，但畫面凍結在觸發快照。
    if (_isSopActive) return;
    final lastClosed = _lastSopClosedTime;
    if (lastClosed != null &&
        DateTime.now().difference(lastClosed) < _sopCooldown) {
      return;
    }

    _isSopActive = true;
    _sopScan = scan;
    _isSopMinimized = false;
    _freezeSnapshot();
    if (mounted) setState(() {});
  }

  Future<void> _completeSop(SopDecision decision) async {
    final scan = _sopScan;
    if (!_isSopActive || scan == null) return;

    // 收合不代表完成；只有使用者選擇結果後才開始 20 秒冷卻。
    _isSopActive = false;
    _sopScan = null;
    _lastSopClosedTime = DateTime.now();
    if (mounted) setState(() {});

    await _persistSopDecision(scan, decision);
  }

  Future<void> _persistSopDecision(
    ScanData scan,
    SopDecision decision,
  ) async {
    // 事件需要 GPS 座標才能顯示在 Safety Map；定位失敗時不建立不完整紀錄。
    final position = await _getCurrentPosition();
    if (position == null || !mounted) return;

    final result = scan.analyze();
    final isDanger = decision == SopDecision.confirmedDanger;
    // SOP 的二態結果直接對應地圖顏色與資料庫決策欄位。
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

  @override
  void dispose() {
    _streamTimer?.cancel();
    _streamTimer = null;
    _snapshotFreezeTimer?.cancel();
    _snapshotFreezeTimer = null;
    _bleSubscription?.cancel();
    _esp32Subscription?.cancel();
    _bleService.dispose();
    _esp32Service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    final grid64x64 = _grid64x64;
    final result = scan?.analyze();
    final levelColor = result == null
        ? Theme.of(context).colorScheme.outline
        : switch (result.level) {
            DetectionLevel.safe => Colors.green,
            DetectionLevel.warning => Colors.orange,
            DetectionLevel.highRisk => Colors.red,
          };

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 180),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (result != null)
                        _StatusCard(
                          level: result.level.label,
                          color: levelColor,
                          deviceName: scan!.deviceName,
                        )
                      else
                        const Text('尚未開始掃描'),
                      const SizedBox(height: 8),
                      Text(_connectionStatus),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed:
                            _isConnecting || _usingHardware || _usingEsp32
                                ? null
                                : connectHardware,
                        icon: _isConnecting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed:
                            _isConnecting || _usingHardware || _usingEsp32
                                ? null
                                : connectEsp32,
                        icon: const Icon(Icons.router),
                        label: Text(
                          _usingEsp32 ? 'ESP32 Wi-Fi 已連線' : '連接 ESP32 Wi-Fi',
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (grid64x64 != null && result != null) ...[
                        ThermalHeatmap64View(
                          temperatures: grid64x64,
                          minTemp: 20.0,
                          maxTemp: 40.0,
                          warningThreshold: 35.0,
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
                                  value:
                                      '${result.deltaT.toStringAsFixed(1)} °C',
                                ),
                                _Metric(
                                  label: 'RSSI',
                                  value:
                                      '${result.rssi.toStringAsFixed(1)} dBm',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
            ),
            if (_isSopActive && _sopScan != null)
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: SopCard(
                        deltaT: _sopScan!.analyze().deltaT,
                        rssi: _sopScan!.analyze().rssi,
                        snapshotFrozen: _isSnapshotFrozen,
                        freezeRemainingSeconds:
                            _snapshotFreezeRemainingSeconds,
                        minimized: _isSopMinimized,
                        onToggleMinimized: () {
                          setState(
                            () => _isSopMinimized = !_isSopMinimized,
                          );
                        },
                        onDecision: _completeSop,
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
