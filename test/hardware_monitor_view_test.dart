import 'package:anti_pinhole/models/cc1101_diagnostic_sample.dart';
import 'package:anti_pinhole/models/scan_data.dart';
import 'package:anti_pinhole/services/hardware_data_monitor.dart';
import 'package:anti_pinhole/services/hardware_connection_service.dart';
import 'package:anti_pinhole/services/thermocam_ble_service.dart';
import 'package:anti_pinhole/home_page.dart';
import 'package:anti_pinhole/views/hardware/hardware_monitor_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the single ThermoCam BLE connection and RSSI values',
      (tester) async {
    final service = HardwareConnectionService();
    await tester.pumpWidget(
      MaterialApp(
        home: HardwareConnectionScope(
          service: service,
          child: const Scaffold(body: HardwareMonitorView()),
        ),
      ),
    );

    expect(find.text('等待熱成像資料'), findsOneWidget);
    expect(find.text('ThermoCam RSSI'), findsOneWidget);
    expect(find.text('CC1101 RSSI'), findsOneWidget);
    expect(find.text('-- dBm'), findsNWidgets(2));
    expect(find.text('目前判定'), findsOneWidget);
    expect(find.text('等待資料'), findsOneWidget);
    expect(find.text('ThermoCam_BLE'), findsOneWidget);
    expect(find.text('連線'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('ESP32 Wi-Fi'), findsNothing);
    expect(find.text('CC1101 藍牙'), findsNothing);

    HardwareDataMonitor.instance.add(
      source: 'ThermoCam BLE',
      rawText: '{"rf_rssi": -62}',
      scan: ScanData(
        id: 'test-scan',
        deviceName: 'ESP32 Thermal Sensor',
        rssi: -62,
        thermalGrid: List<double>.filled(64, 28),
        capturedAt: '2026-10-22T12:00:00Z',
      ),
    );
    HardwareDataMonitor.instance.add(
      source: 'CC1101',
      rawText: '{"rssi": -71}',
      cc1101Sample: Cc1101DiagnosticSample(
        capturedAt: DateTime.utc(2026, 10, 22, 12),
        rssi: -71,
        lqi: 45,
        crcOk: true,
        receivedPackets: 10,
        lostPackets: 1,
        per: 0.1,
        distanceMeters: 3,
        rawJson: const {'rssi': -71},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('ThermoCam RSSI'), findsOneWidget);
    expect(find.text('CC1101 RSSI'), findsOneWidget);
    expect(find.text('-62.0 dBm'), findsOneWidget);
    expect(find.text('-71.0 dBm'), findsOneWidget);
    expect(find.text('警示'), findsOneWidget);
    expect(find.text('最低溫度'), findsOneWidget);
    expect(find.text('最高溫度'), findsOneWidget);
    expect(find.text('平均溫度'), findsOneWidget);
    expect(find.text('高風險排查 SOP'), findsNothing);
    expect(find.text('停止掃描'), findsNothing);
    expect(find.text('訊號列表'), findsNothing);
    expect(find.text('原始資料與解析狀態'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('shows SOP for high-risk scan data', (tester) async {
    final service = HardwareConnectionService();
    await tester.pumpWidget(
      MaterialApp(
        home: HardwareConnectionScope(
          service: service,
          child: const Scaffold(body: HardwareMonitorView()),
        ),
      ),
    );

    final thermalGrid = List<double>.filled(64, 24);
    thermalGrid[0] = 31;
    HardwareDataMonitor.instance.add(
      source: 'test',
      rawText: '',
      scan: ScanData(
        id: 'high-risk-scan',
        deviceName: 'Test sensor',
        rssi: -45,
        thermalGrid: thermalGrid,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('高風險排查 SOP'), findsOneWidget);
    expect(find.text('關燈排查'), findsOneWidget);

    await tester.tap(find.text('複檢正常（疑似誤判）'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('falls back to mock scans when ThermoCam BLE is unavailable',
      (tester) async {
    final service = HardwareConnectionService(
      bleService: _FailingThermoCamBleService(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HardwareConnectionScope(
          service: service,
          child: const Scaffold(body: HardwareMonitorView()),
        ),
      ),
    );

    await tester.ensureVisible(find.text('連線'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('連線'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('模擬模式 · 未連接硬體'), findsOneWidget);
    expect(find.text('停止模擬'), findsOneWidget);
    expect(find.text('等待熱成像資料'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('shares ThermoCam BLE connection and data across pages',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = HardwareConnectionService(
      bleService: _FakeThermoCamBleService(),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => HardwareConnectionScope(
          service: service,
          child: child!,
        ),
        home: const HomePage(),
      ),
    );

    final bleCard = find.ancestor(
      of: find.text('ThermoCam_BLE'),
      matching: find.byType(Card),
    );
    await tester.ensureVisible(bleCard.first);
    await tester.tap(
      find.descendant(of: bleCard.first, matching: find.text('連線')),
    );
    await tester.pumpAndSettle();
    expect(
      service.stateFor(HardwareConnectionType.thermocamBluetooth).status,
      HardwareConnectionStatus.connected,
    );

    HardwareDataMonitor.instance.add(
      source: 'test',
      rawText: '',
      scan: ScanData(
        id: 'shared-scan',
        deviceName: 'Shared sensor',
        rssi: -62,
        thermalGrid: List<double>.filled(64, 28),
      ),
    );
    HardwareDataMonitor.instance.add(
      source: 'test',
      rawText: '',
      cc1101Sample: Cc1101DiagnosticSample(
        capturedAt: DateTime.utc(2026, 10, 22, 12),
        rssi: -71,
        lqi: 45,
        crcOk: true,
        receivedPackets: 10,
        lostPackets: 1,
        per: 0.1,
        distanceMeters: 3,
        rawJson: const {'rssi': -71},
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('熱成像'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('-62.0 dBm'), findsOneWidget);
    expect(find.text('Shared sensor'), findsOneWidget);
    expect(find.text('ThermoCam_BLE · Connected'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CC1101 診斷'));
    await tester.pumpAndSettle();
    expect(find.text('-71.0 dBm'), findsOneWidget);
    expect(find.text('ThermoCam_BLE · Connected'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(Drawer),
            matching: find.text('硬體監控'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('斷線'));
    await tester.pumpAndSettle();
    expect(
      service.stateFor(HardwareConnectionType.thermocamBluetooth).status,
      HardwareConnectionStatus.disconnected,
    );

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('熱成像'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Disconnected'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });
}

class _FakeThermoCamBleService extends ThermoCamBleService {
  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}

class _FailingThermoCamBleService extends ThermoCamBleService {
  @override
  Future<void> connect() async {
    throw StateError('BLE unavailable');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}
