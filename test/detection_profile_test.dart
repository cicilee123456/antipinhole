import 'package:flutter_test/flutter_test.dart';

import 'package:anti_pinhole/models/scan_data.dart';

void main() {
  final scan = ScanData(
    id: 'profile-test',
    deviceName: 'Test sensor',
    rssi: -70,
    thermalGrid: List<double>.filled(64, 25),
  );

  test('passes the environment mode and thermal state to the result', () {
    const profile = DetectionProfile(
      environmentMode: HeatEnvironmentMode.noHeatSource,
      thermalEnabled: false,
    );

    final result = scan.analyze(profile);

    expect(result.profile.environmentMode, HeatEnvironmentMode.noHeatSource);
    expect(result.profile.thermalEnabled, isFalse);
  });

  test('first phase profile does not change the existing RSSI score', () {
    const profile = DetectionProfile(
      environmentMode: HeatEnvironmentMode.noHeatSource,
      thermalEnabled: false,
    );

    final result = scan.analyze(profile);

    expect(result.level, DetectionLevel.highRisk);
    expect(result.weightedScore, closeTo(19 / 89, 0.000001));
  });
}
