import 'package:anti_pinhole/models/cc1101_diagnostic_sample.dart';
import 'package:anti_pinhole/models/scan_data.dart';
import 'package:anti_pinhole/services/hardware_data_monitor.dart';
import 'package:anti_pinhole/views/hardware/hardware_monitor_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows only the thermal view and two RSSI values',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HardwareMonitorView()),
      ),
    );

    expect(find.text('等待熱成像資料'), findsOneWidget);
    expect(find.text('ESP32 RSSI'), findsOneWidget);
    expect(find.text('CC1101 RSSI'), findsOneWidget);
    expect(find.text('-- dBm'), findsNWidgets(2));
    expect(find.text('目前判定'), findsOneWidget);
    expect(find.text('等待資料'), findsOneWidget);
    expect(find.text('開始掃描'), findsOneWidget);

    HardwareDataMonitor.instance.add(
      source: 'ESP32 HTTP',
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

    expect(find.text('ESP32 RSSI'), findsOneWidget);
    expect(find.text('CC1101 RSSI'), findsOneWidget);
    expect(find.text('-62.0 dBm'), findsOneWidget);
    expect(find.text('-71.0 dBm'), findsOneWidget);
    expect(find.text('警示'), findsOneWidget);
    expect(find.text('最低溫度'), findsOneWidget);
    expect(find.text('最高溫度'), findsOneWidget);
    expect(find.text('平均溫度'), findsOneWidget);
    expect(find.text('停止掃描'), findsNothing);
    expect(find.text('訊號列表'), findsNothing);
    expect(find.text('原始資料與解析狀態'), findsNothing);
  });

  testWidgets('falls back to mock scans when ESP32 is unavailable',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HardwareMonitorView()),
      ),
    );

    await tester.ensureVisible(find.text('開始掃描'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始掃描'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('模擬模式 · 未連接硬體'), findsOneWidget);
    expect(find.text('停止掃描'), findsOneWidget);
    expect(find.text('等待熱成像資料'), findsNothing);
  });
}
