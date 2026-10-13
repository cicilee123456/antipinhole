import 'package:flutter_test/flutter_test.dart';

import 'package:anti_pinhole/models/cc1101_diagnostic_sample.dart';

void main() {
  test('parses CC1101 metrics and calculates PER from packet counts', () {
    final sample = Cc1101DiagnosticSample.fromJson({
      'captured_at': '2026-10-01T08:00:00Z',
      'cc1101': {
        'rssi': -61.5,
        'lqi': 42,
        'crc_ok': true,
        'received_packets': 980,
        'lost_packets': 20,
        'distance_m': 5,
      },
    });

    expect(sample.rssi, -61.5);
    expect(sample.lqi, 42);
    expect(sample.crcOk, isTrue);
    expect(sample.receivedPackets, 980);
    expect(sample.lostPackets, 20);
    expect(sample.per, 0.02);
    expect(sample.distanceMeters, 5);
  });

  test('keeps unsupported metrics unavailable instead of inventing values', () {
    final sample = Cc1101DiagnosticSample.fromJson({'rf_rssi': -70});

    expect(sample.rssi, -70);
    expect(sample.lqi, isNull);
    expect(sample.crcOk, isNull);
    expect(sample.per, isNull);
    expect(sample.distanceMeters, isNull);
  });
}
