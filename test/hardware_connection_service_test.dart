import 'dart:async';

import 'package:anti_pinhole/models/cc1101_diagnostic_sample.dart';
import 'package:anti_pinhole/models/scan_data.dart';
import 'package:anti_pinhole/services/hardware_connection_service.dart';
import 'package:anti_pinhole/services/hardware_data_monitor.dart';
import 'package:anti_pinhole/services/esp32_ble_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('publishes connection transitions and disconnects centrally', () async {
    final connectCompleter = Completer<void>();
    final bleService = _ControlledBleService(connectCompleter);
    final service = HardwareConnectionService(bleService: bleService);

    final connectFuture = service.connect(
      HardwareConnectionType.esp32Bluetooth,
    );
    expect(
      service.stateFor(HardwareConnectionType.esp32Bluetooth).status,
      HardwareConnectionStatus.connecting,
    );

    connectCompleter.complete();
    await connectFuture;
    expect(
      service.stateFor(HardwareConnectionType.esp32Bluetooth).status,
      HardwareConnectionStatus.connected,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(service.esp32Rssi, -48);
    expect(service.esp32RssiError, isNull);

    await service.disconnect();
    expect(
      service.stateFor(HardwareConnectionType.esp32Bluetooth).status,
      HardwareConnectionStatus.disconnected,
    );
    expect(service.esp32Rssi, isNull);
    service.dispose();
  });

  test('retains the connection error after a failed connection attempt',
      () async {
    final service = HardwareConnectionService(
      bleService: _FailingBleService(),
    );

    await expectLater(
      service.connect(HardwareConnectionType.esp32Bluetooth),
      throwsStateError,
    );
    final state = service.stateFor(HardwareConnectionType.esp32Bluetooth);
    expect(state.status, HardwareConnectionStatus.error);
    expect(state.error, contains('BLE unavailable'));
    expect(service.activeConnection, isNull);
    service.dispose();
  });

  test('turns BLE thermal telemetry into the shared scan and risk event',
      () async {
    final service = HardwareConnectionService();
    final riskFuture = service.riskEvents.first;
    final pixels = List<double>.filled(64, 24)..[0] = 32;

    HardwareDataMonitor.instance.add(
      source: 'CC1101 BLE',
      rawText: '',
      cc1101Sample: Cc1101DiagnosticSample(
        capturedAt: DateTime.utc(2026, 11, 12),
        rssi: -45,
        lqi: 40,
        crcOk: true,
        receivedPackets: 10,
        lostPackets: 0,
        per: 0,
        distanceMeters: null,
        rawJson: const {},
        thermalPixels: pixels,
        irDetected: true,
      ),
    );

    final riskScan = await riskFuture.timeout(const Duration(seconds: 1));
    expect(service.latestScan?.thermalGrid, pixels);
    expect(service.latestScan?.rssi, -45);
    expect(service.latestScan?.irDetected, isTrue);
    expect(riskScan.analyze().deltaT, 8);
    service.dispose();
  });

  test('publishes Wi-Fi characteristic updates through shared state', () async {
    final service = HardwareConnectionService();
    const networks = [
      WifiAccessPoint(
        ssid: 'My,Home WiFi',
        rssi: -62,
        distanceMeters: 1.9,
      ),
    ];

    HardwareDataMonitor.instance.add(
      source: 'Wi-Fi BLE',
      rawText: 'Wi-Fi AP 清單完成（1 筆）',
      wifiNetworks: networks,
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.latestWifiNetworks, networks);
    service.dispose();
  });

  test('emits one risk event and retries after cooldown while risk remains',
      () async {
    final service = HardwareConnectionService(
      sopCooldown: const Duration(milliseconds: 100),
    );
    final riskScans = <ScanData>[];
    final subscription = service.riskEvents.listen(riskScans.add);

    HardwareDataMonitor.instance.add(
      source: 'test',
      rawText: '',
      scan: _scan('high-1', maxTemperature: 30, rssi: -50),
    );
    HardwareDataMonitor.instance.add(
      source: 'test',
      rawText: '',
      scan: _scan('high-2', maxTemperature: 30, rssi: -50),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(riskScans, hasLength(1));

    HardwareDataMonitor.instance.add(
      source: 'test',
      rawText: '',
      scan: _scan('safe', maxTemperature: 29, rssi: -50),
    );
    HardwareDataMonitor.instance.add(
      source: 'test',
      rawText: '',
      scan: _scan('cooldown-high', maxTemperature: 30, rssi: -50),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(riskScans, hasLength(1));

    await Future<void>.delayed(const Duration(milliseconds: 110));
    HardwareDataMonitor.instance.add(
      source: 'test',
      rawText: '',
      scan: _scan('after-cooldown-high', maxTemperature: 30, rssi: -50),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(riskScans, hasLength(2));

    await Future<void>.delayed(const Duration(milliseconds: 110));
    HardwareDataMonitor.instance.add(
      source: 'test',
      rawText: '',
      scan: _scan('sustained-high', maxTemperature: 30, rssi: -50),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(riskScans, hasLength(3));

    await subscription.cancel();
    service.dispose();
  });
}

ScanData _scan(
  String id, {
  required double maxTemperature,
  required double rssi,
}) {
  final grid = List<double>.filled(64, 24);
  grid[0] = maxTemperature;
  return ScanData(
    id: id,
    deviceName: 'Test sensor',
    rssi: rssi,
    thermalGrid: grid,
  );
}

class _ControlledBleService extends Esp32BleService {
  _ControlledBleService(this.connectCompleter);

  final Completer<void> connectCompleter;

  @override
  Future<void> connect() => connectCompleter.future;

  @override
  Future<void> disconnect() async {}

  @override
  Future<int> readRssi() async => -48;

  @override
  Future<void> dispose() async {}
}

class _FailingBleService extends Esp32BleService {
  @override
  Future<void> connect() async {
    throw StateError('BLE unavailable');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}
