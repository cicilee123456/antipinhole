import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/cc1101_diagnostic_sample.dart';
import '../models/scan_data.dart';
import 'hardware_data_monitor.dart';
import 'thermal_simulator.dart';
import 'thermocam_ble_service.dart';

enum HardwareConnectionType { thermocamBluetooth }

enum HardwareConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class HardwareConnectionState {
  const HardwareConnectionState({
    this.status = HardwareConnectionStatus.disconnected,
    this.error,
  });

  final HardwareConnectionStatus status;
  final String? error;
}

class HardwareConnectionService extends ChangeNotifier {
  HardwareConnectionService({
    ThermoCamBleService? bleService,
    this.sopCooldown = const Duration(seconds: 20),
  }) : _bleService = bleService ?? ThermoCamBleService() {
    _dataSubscription =
        HardwareDataMonitor.instance.events.listen(_handleDataEvent);
  }

  static const _simulator = ThermalSimulator();

  final Duration sopCooldown;
  final ThermoCamBleService _bleService;
  final _random = Random();
  final _states = {
    HardwareConnectionType.thermocamBluetooth: const HardwareConnectionState(),
  };
  final _eventsController = StreamController<HardwareDataEvent>.broadcast();
  final _riskController = StreamController<ScanData>.broadcast();

  StreamSubscription<HardwareDataEvent>? _dataSubscription;
  Timer? _simulationTimer;
  HardwareConnectionType? _activeConnection;
  ScanData? _latestScan;
  Cc1101DiagnosticSample? _latestCc1101Sample;
  DateTime? _lastRiskAt;
  bool _isClosed = false;

  Stream<HardwareDataEvent> get events => _eventsController.stream;
  Stream<ScanData> get riskEvents => _riskController.stream;
  ScanData? get latestScan => _latestScan;
  Cc1101DiagnosticSample? get latestCc1101Sample => _latestCc1101Sample;
  HardwareConnectionType? get activeConnection => _activeConnection;
  bool get isSimulating => _simulationTimer != null;

  HardwareConnectionType? get failedConnection {
    for (final type in HardwareConnectionType.values) {
      if (_states[type]?.status == HardwareConnectionStatus.error) return type;
    }
    return null;
  }

  bool get isScanning =>
      isSimulating ||
      (_activeConnection != null &&
          _states[_activeConnection]?.status ==
              HardwareConnectionStatus.connected);

  HardwareConnectionState stateFor(HardwareConnectionType type) =>
      _states[type]!;

  bool get canConnect => _activeConnection == null && !isSimulating;

  Future<void> connect(
    HardwareConnectionType type, {
    bool fallbackToSimulator = false,
  }) async {
    if (_isClosed) throw StateError('硬體連線服務已關閉');
    if (_activeConnection == type &&
        stateFor(type).status == HardwareConnectionStatus.connected) {
      return;
    }
    if (!canConnect) {
      throw StateError('請先中斷目前的連線或停止模擬掃描');
    }

    _activeConnection = type;
    _setState(
        type,
        const HardwareConnectionState(
          status: HardwareConnectionStatus.connecting,
        ));

    try {
      await _bleService.connect();

      if (_isClosed) return;
      _setState(
          type,
          const HardwareConnectionState(
            status: HardwareConnectionStatus.connected,
          ));
    } catch (error) {
      try {
        await _releaseConnection(type);
      } catch (cleanupError) {
        if (!_isClosed) _setConnectionError(type, cleanupError);
        rethrow;
      }
      if (_isClosed) return;
      _setConnectionError(type, error);
      if (fallbackToSimulator) {
        _startSimulator();
        return;
      }
      rethrow;
    }
  }

  Future<void> disconnect([HardwareConnectionType? type]) async {
    final connection = type ?? _activeConnection;
    if (connection == null) {
      stopSimulation();
      return;
    }
    if (_activeConnection != connection) return;

    _setState(
        connection,
        const HardwareConnectionState(
          status: HardwareConnectionStatus.connecting,
        ));
    try {
      await _releaseConnection(connection);
      if (!_isClosed) {
        _setState(connection, const HardwareConnectionState());
      }
    } catch (error) {
      if (!_isClosed) _setConnectionError(connection, error);
      rethrow;
    }
  }

  void _handleDataEvent(HardwareDataEvent event) {
    if (_isClosed) return;
    if (event.scan != null) {
      _latestScan = event.scan;
      _checkRisk(event.scan!);
    }
    if (event.cc1101Sample != null) {
      _latestCc1101Sample = event.cc1101Sample;
    }
    _eventsController.add(event);
    notifyListeners();
  }

  void _checkRisk(ScanData scan) {
    final result = scan.analyze();
    final highRisk = result.deltaT >= 6.0 && result.rssi >= -50.0;
    if (!highRisk) return;

    final lastRiskAt = _lastRiskAt;
    if (lastRiskAt != null &&
        DateTime.now().difference(lastRiskAt) < sopCooldown) {
      return;
    }
    _lastRiskAt = DateTime.now();
    _riskController.add(scan);
  }

  void _startSimulator() {
    if (_simulationTimer != null || _isClosed) return;
    _activeConnection = null;
    _simulationTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _publishSimulatedData(),
    );
    _publishSimulatedData();
    notifyListeners();
  }

  void stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    notifyListeners();
  }

  void _publishSimulatedData() {
    final scan = _simulator.scan();
    HardwareDataMonitor.instance.add(
      source: '熱成像模擬資料',
      rawText: '',
      scan: scan,
    );
    final sample = Cc1101DiagnosticSample(
      capturedAt: DateTime.now(),
      rssi: -90 + _random.nextDouble() * 45,
      lqi: null,
      crcOk: null,
      receivedPackets: null,
      lostPackets: null,
      per: null,
      distanceMeters: null,
      rawJson: const {'simulated': true},
    );
    HardwareDataMonitor.instance.add(
      source: 'CC1101 模擬資料',
      rawText: sample.toJsonLine(),
      cc1101Sample: sample,
    );
  }

  Future<void> _releaseConnection(HardwareConnectionType type) async {
    await _bleService.disconnect();
    _activeConnection = null;
  }

  void _setConnectionError(HardwareConnectionType type, Object error) {
    _activeConnection = null;
    _setState(
      type,
      HardwareConnectionState(
        status: HardwareConnectionStatus.error,
        error: error.toString(),
      ),
    );
  }

  void _setState(HardwareConnectionType type, HardwareConnectionState state) {
    _states[type] = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _isClosed = true;
    _simulationTimer?.cancel();
    unawaited(_dataSubscription?.cancel());
    unawaited(_eventsController.close());
    unawaited(_riskController.close());
    unawaited(_bleService.dispose());
    super.dispose();
  }
}

class HardwareConnectionScope
    extends InheritedNotifier<HardwareConnectionService> {
  const HardwareConnectionScope({
    required this.service,
    required super.child,
    super.key,
  }) : super(notifier: service);

  final HardwareConnectionService service;

  static HardwareConnectionService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<HardwareConnectionScope>();
    if (scope == null) {
      throw FlutterError(
        'HardwareConnectionScope is missing from this context.',
      );
    }
    return scope.service;
  }
}
