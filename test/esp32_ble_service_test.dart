import 'dart:convert';

import 'package:anti_pinhole/models/cc1101_diagnostic_sample.dart';
import 'package:anti_pinhole/services/esp32_ble_service.dart';
import 'package:anti_pinhole/services/hardware_data_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the BLE device name and UUIDs advertised by the firmware', () {
    expect(Esp32BleService.deviceName, 'CC1101_BLE');
    expect(
      Esp32BleService.serviceUuid,
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
    );
    expect(
      Esp32BleService.characteristicUuid,
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
    );
  });

  test('assembles firmware JSON notifications into shared CC1101 data',
      () async {
    final service = Esp32BleService();
    const payload = '{"captured_at":1234,"rssi":-71.5,"lqi":42,"crc_ok":true,'
        '"received_packets":12,"lost_packets":2,"per":0.1428}';
    final bytes = utf8.encode(payload);
    final eventFuture = HardwareDataMonitor.instance.events.firstWhere(
      (event) => event.source == 'CC1101 BLE',
    );

    service.handleNotification(bytes.sublist(0, 24));
    service.handleNotification(bytes.sublist(24));

    final event = await eventFuture.timeout(const Duration(seconds: 1));
    expect(event.isParsed, isTrue);
    expect(event.scan, isNull);
    expect(event.cc1101Sample?.rssi, -71.5);
    expect(event.cc1101Sample?.lqi, 42);
    expect(event.cc1101Sample?.crcOk, isTrue);
    expect(event.cc1101Sample?.receivedPackets, 12);
    expect(event.cc1101Sample?.lostPackets, 2);
    expect(event.cc1101Sample?.per, 0.1428);

    await service.dispose();
  });

  test('parses AMG8833 pixels and VS1838B IR telemetry when supplied',
      () async {
    final thermalPixels = List<double>.generate(64, (index) => 20 + index / 10);
    final sample = Cc1101DiagnosticSample.fromJson({
      'rssi': -68,
      'amg8833': {'pixels': thermalPixels},
      'vs1838b': {
        'detected': true,
        'protocol': 'NEC',
        'address': '0x1234',
        'command': '0x56',
      },
    });

    expect(sample.thermalPixels, thermalPixels);
    expect(sample.irDetected, isTrue);
    expect(sample.irProtocol, 'NEC');
    expect(sample.irAddress, '0x1234');
    expect(sample.irCommand, '0x56');
  });

  test('does not claim AMG8833 or VS1838B data when firmware omits it', () {
    final sample = Cc1101DiagnosticSample.fromJson({
      'rssi': -68,
      'lqi': 42,
    });

    expect(sample.thermalPixels, isNull);
    expect(sample.irDetected, isNull);
    expect(sample.irProtocol, isNull);
  });
}
