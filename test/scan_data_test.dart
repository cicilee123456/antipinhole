import 'package:anti_pinhole/models/scan_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DetectionAnalyzer', () {
    test('requires both high temperature delta and strong RSSI for high risk',
        () {
      expect(
          _scan(deltaT: 6, rssi: -50).analyze().level, DetectionLevel.highRisk);
      expect(
          _scan(deltaT: 6, rssi: -51).analyze().level, DetectionLevel.warning);
      expect(_scan(deltaT: 5.9, rssi: -50).analyze().level,
          DetectionLevel.warning);
    });

    test('reports warning when either warning threshold is reached', () {
      expect(
          _scan(deltaT: 4, rssi: -80).analyze().level, DetectionLevel.warning);
      expect(
          _scan(deltaT: 2, rssi: -65).analyze().level, DetectionLevel.warning);
      expect(
          _scan(deltaT: 3.9, rssi: -66).analyze().level, DetectionLevel.safe);
    });

    test('combines thermal and signal scores', () {
      final result = _scan(deltaT: 6, rssi: -50).analyze();

      expect(result.weightedScore, closeTo(0.6 + 0.4, 0.0001));
    });
  });

  test('parses ESP32 thermal_grid and ESP32RSSI fields', () {
    final scan = ScanData.fromEsp32Json({
      'thermal_grid': List<double>.filled(64, 28),
      'ESP32RSSI': -65,
    });

    expect(scan.thermalGrid, hasLength(64));
    expect(scan.rssi, -65);
  });
}

ScanData _scan({required double deltaT, required double rssi}) {
  return ScanData(
    id: 'test',
    deviceName: 'test sensor',
    rssi: rssi,
    thermalGrid: [24.0, ...List<double>.filled(62, 24.0), 24.0 + deltaT],
  );
}
