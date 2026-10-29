import 'package:flutter_test/flutter_test.dart';

import 'package:anti_pinhole/models/scan_data.dart';
import 'package:anti_pinhole/models/vs1838b_sample.dart';

void main() {
  test('parses VS1838B data nested in a hardware payload', () {
    final sample = Vs1838bSample.fromJson({
      'vs1838b': {
        'detected': true,
        'code': '0x20DF10EF',
        'protocol': 'NEC',
        'repeat': false,
      },
    });

    expect(sample.detected, isTrue);
    expect(sample.code, '0x20DF10EF');
    expect(sample.protocol, 'NEC');
    expect(sample.repeat, isFalse);
  });

  test('keeps VS1838B data with thermal scans', () {
    final scan = ScanData.fromHardwareJson({
      'thermal': List<double>.filled(64, 25),
      'rf': -70,
      'vs1838b': {'detected': 1},
    }, deviceId: 'sensor', deviceName: 'ThermoCam');

    expect(scan.vs1838b?.detected, isTrue);
  });

  test('does not report VS1838B when a payload has no IR fields', () {
    final scan = ScanData.fromHardwareJson({
      'thermal': List<double>.filled(64, 25),
      'rf': -70,
    }, deviceId: 'sensor', deviceName: 'ThermoCam');

    expect(scan.vs1838b, isNull);
  });
}
