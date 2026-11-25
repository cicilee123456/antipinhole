import 'package:anti_pinhole/models/cc1101_diagnostic_sample.dart';
import 'package:anti_pinhole/models/scan_data.dart';
import 'package:anti_pinhole/services/hardware_data_monitor.dart';
import 'package:anti_pinhole/services/hardware_connection_service.dart';
import 'package:anti_pinhole/services/esp32_ble_service.dart';
import 'package:anti_pinhole/home_page.dart';
import 'package:anti_pinhole/views/hardware/hardware_monitor_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the single ESP32 BLE connection and RSSI values',
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
    expect(find.text('Wi-Fi 偵測'), findsOneWidget);
    expect(find.text('點擊查看'), findsOneWidget);
    expect(find.text('此平台不支援'), findsNothing);
    expect(find.text('風險判定 RSSI'), findsOneWidget);
    expect(find.text('CC1101 RSSI'), findsOneWidget);
    expect(find.text('-- dBm'), findsNWidgets(2));
    expect(find.text('感測器資料'), findsOneWidget);
    expect(find.text('AMG8833 熱像'), findsOneWidget);
    expect(find.text('VS1838B 紅外線'), findsOneWidget);
    expect(find.text('韌體尚未透過 BLE 上報'), findsNWidgets(2));
    expect(find.text('目前判定'), findsOneWidget);
    expect(find.text('等待資料'), findsOneWidget);
    expect(find.text('ESP32 ThermoCam'), findsOneWidget);
    expect(find.text('連線'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('ESP32 Wi-Fi'), findsNothing);
    expect(find.text('CC1101 藍牙'), findsNothing);

    HardwareDataMonitor.instance.add(
      source: '熱像掃描',
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
        thermalPixels: List<double>.filled(64, 29),
        irDetected: true,
        irProtocol: 'NEC',
        irAddress: '0x1234',
        irCommand: '0x56',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('風險判定 RSSI'), findsOneWidget);
    expect(find.text('Wi-Fi 偵測'), findsOneWidget);
    expect(find.text('CC1101 RSSI'), findsOneWidget);
    expect(find.text('-62.0 dBm'), findsNothing);
    expect(find.text('-71.0 dBm'), findsNWidgets(2));
    expect(
        find.textContaining('64 格 · 29.0–29.0 °C · ΔT 0.0 °C'), findsOneWidget);
    expect(find.textContaining('偵測到紅外線'), findsOneWidget);
    expect(find.text('安全'), findsOneWidget);
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

  testWidgets('opens the Wi-Fi AP list with RSSI and distance', (tester) async {
    final service = HardwareConnectionService();
    await tester.pumpWidget(
      MaterialApp(
        home: HardwareConnectionScope(
          service: service,
          child: const Scaffold(body: HardwareMonitorView()),
        ),
      ),
    );

    HardwareDataMonitor.instance.add(
      source: 'ThermoCam BLE',
      rawText: '',
      cc1101Sample: Cc1101DiagnosticSample(
        capturedAt: DateTime.utc(2026, 11, 18),
        rssi: -65,
        lqi: null,
        crcOk: null,
        receivedPackets: null,
        lostPackets: null,
        per: null,
        distanceMeters: null,
        rawJson: const {},
        wifiDeviceCount: 2,
        wifiNetworks: const [
          WifiAccessPoint(
            ssid: 'Lab WiFi',
            rssi: -48,
            distanceMeters: 0.55,
          ),
          WifiAccessPoint(
            ssid: 'Guest',
            rssi: -72,
            distanceMeters: 4.25,
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('點擊查看'));
    await tester.tap(find.text('點擊查看'));
    await tester.pumpAndSettle();

    expect(find.text('Wi-Fi 偵測 (2)'), findsOneWidget);
    expect(find.text('Lab WiFi'), findsOneWidget);
    expect(find.text('RSSI -48.0 dBm'), findsOneWidget);
    expect(find.text('0.55 m'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('RSSI -72.0 dBm'), findsOneWidget);
    expect(find.text('4.25 m'), findsOneWidget);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('shows Wi-Fi details received on the second BLE characteristic',
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

    HardwareDataMonitor.instance.add(
      source: 'Wi-Fi BLE',
      rawText: 'Wi-Fi AP 清單完成（1 筆）',
      wifiNetworks: const [
        WifiAccessPoint(
          ssid: 'My,Home WiFi',
          rssi: -62,
          distanceMeters: 1.9,
        ),
      ],
    );
    await tester.pump();
    await tester.ensureVisible(find.text('點擊查看'));
    await tester.tap(find.text('點擊查看'));
    await tester.pumpAndSettle();

    expect(find.text('My,Home WiFi'), findsOneWidget);
    expect(find.text('RSSI -62.0 dBm'), findsOneWidget);
    expect(find.text('1.90 m'), findsOneWidget);

    await tester.tap(find.text('關閉'));
    await tester.pumpAndSettle();
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

  testWidgets('shows BLE connection errors without starting mock scans',
      (tester) async {
    final service = HardwareConnectionService(
      bleService: _FailingEsp32BleService(),
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
    await tester.pumpAndSettle();

    expect(find.textContaining('Bad state: BLE unavailable'), findsNWidgets(2));
    expect(find.text('模擬模式 · 未連接硬體'), findsNothing);
    expect(find.text('停止模擬'), findsNothing);
    expect(find.text('等待熱成像資料'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets('shares ESP32 BLE connection and data across pages',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = HardwareConnectionService(
      bleService: _FakeEsp32BleService(),
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
      of: find.text('ESP32 ThermoCam'),
      matching: find.byType(Card),
    );
    await tester.ensureVisible(bleCard.first);
    await tester.tap(
      find.descendant(of: bleCard.first, matching: find.text('連線')),
    );
    await tester.pumpAndSettle();
    expect(
      service.stateFor(HardwareConnectionType.esp32Bluetooth).status,
      HardwareConnectionStatus.connected,
    );
    await tester.pump();
    expect(find.text('點擊查看'), findsOneWidget);
    expect(find.text('ESP32 BLE RSSI'), findsNothing);
    expect(
      find.textContaining('ESP32 未提供有效的 64 格熱像資料'),
      findsOneWidget,
    );

    final thermalPixels = List<double>.filled(64, 24)..[0] = 28;
    HardwareDataMonitor.instance.add(
      source: 'CC1101 BLE',
      rawText: '',
      cc1101Sample: Cc1101DiagnosticSample(
        capturedAt: DateTime.utc(2026, 11, 12, 12),
        rssi: -70,
        lqi: 40,
        crcOk: true,
        receivedPackets: 10,
        lostPackets: 0,
        per: 0,
        distanceMeters: null,
        rawJson: const {},
        thermalPixels: thermalPixels,
        irDetected: false,
        rfDetected: false,
      ),
    );
    await tester.pump();
    expect(service.latestScan?.thermalGrid, thermalPixels);
    await tester.ensureVisible(find.text('AMG8833 熱像'));
    await tester.pump();
    expect(find.textContaining('ΔT 4.0 °C'), findsOneWidget);
    expect(find.textContaining('目前無 RF 封包'), findsOneWidget);
    expect(
      find.textContaining('ESP32 未提供有效的 64 格熱像資料'),
      findsNothing,
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
    expect(find.text('ESP32 ThermoCam · Connected'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CC1101 診斷'));
    await tester.pumpAndSettle();
    expect(find.text('-71.0 dBm'), findsOneWidget);
    expect(find.text('ESP32 ThermoCam · Connected'), findsOneWidget);

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
    await tester.ensureVisible(find.text('斷線'));
    await tester.tap(find.text('斷線'));
    await tester.pumpAndSettle();
    expect(
      service.stateFor(HardwareConnectionType.esp32Bluetooth).status,
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

class _FakeEsp32BleService extends Esp32BleService {
  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<int> readRssi() async => -52;

  @override
  Future<void> dispose() async {}
}

class _FailingEsp32BleService extends Esp32BleService {
  @override
  Future<void> connect() async {
    throw StateError('BLE unavailable');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}
