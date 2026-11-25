import 'dart:convert';

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
    expect(Esp32BleService.thermoCamDeviceName, 'ThermoCam_BLE');
    expect(
      Esp32BleService.thermoCamServiceUuid,
      '4fafc201-1fb5-459e-8fcc-c5c9c331914b',
    );
    expect(
      Esp32BleService.thermoCamCharacteristicUuid,
      'beb5483e-36e1-4688-b7f5-ea07361b26a8',
    );
    expect(
      Esp32BleService.wifiListCharacteristicUuid,
      'beb5483e-36e1-4688-b7f5-ea07361b26a9',
    );
  });

  test('publishes the Wi-Fi characteristic list only after END', () async {
    final service = Esp32BleService();
    final receivedEvents = <HardwareDataEvent>[];
    final subscription = HardwareDataMonitor.instance.events
        .where((event) => event.source == 'Wi-Fi BLE')
        .listen(receivedEvents.add);

    service.handleWifiListNotification(utf8.encode('START'));
    service.handleWifiListNotification(utf8.encode('-80,4.2,Old network'));
    service.handleWifiListNotification(utf8.encode('START'));
    service.handleWifiListNotification(utf8.encode('-62,1.9,My,Home WiFi'));
    service.handleWifiListNotification(utf8.encode('-70,3.0,訪客網路'));
    expect(receivedEvents, isEmpty);

    service.handleWifiListNotification(utf8.encode('END'));
    await Future<void>.delayed(Duration.zero);

    expect(receivedEvents, hasLength(1));
    final event = receivedEvents.single;
    expect(event.isParsed, isTrue);
    expect(event.wifiNetworks, hasLength(2));
    expect(event.wifiNetworks![0].ssid, 'My,Home WiFi');
    expect(event.wifiNetworks![0].rssi, -62);
    expect(event.wifiNetworks![0].distanceMeters, 1.9);
    expect(event.wifiNetworks![1].ssid, '訪客網路');

    await subscription.cancel();
    await service.dispose();
  });

  test('reports Wi-Fi rows outside a START and END sequence', () async {
    final service = Esp32BleService();
    final eventFuture = HardwareDataMonitor.instance.events.firstWhere(
      (event) => event.source == 'Wi-Fi BLE',
    );

    service.handleWifiListNotification(utf8.encode('-62,1.9,MyHomeWiFi'));

    final event = await eventFuture.timeout(const Duration(seconds: 1));
    expect(event.isParsed, isFalse);
    expect(event.error, contains('不在 START/END'));
    await service.dispose();
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

  test('assembles split UTF-8 Wi-Fi telemetry and parses AP details', () async {
    final service = Esp32BleService();
    const payload = '{"wifi_count":1,"wifi_networks":['
        '{"ssid":"家中 WiFi","rssi":-53,"distance_m":1.2}]}';
    final bytes = utf8.encode(payload);
    final splitAt = bytes.indexOf(0xE5) + 1;
    final eventFuture = HardwareDataMonitor.instance.events.firstWhere(
      (event) => event.source == 'CC1101 BLE',
    );

    service.handleNotification(bytes.sublist(0, splitAt));
    service.handleNotification(bytes.sublist(splitAt));

    final event = await eventFuture.timeout(const Duration(seconds: 1));
    expect(event.isParsed, isTrue);
    expect(event.cc1101Sample?.wifiDeviceCount, 1);
    expect(event.cc1101Sample?.wifiNetworks.single.ssid, '家中 WiFi');
    expect(event.cc1101Sample?.wifiNetworks.single.rssi, -53);
    expect(event.cc1101Sample?.wifiNetworks.single.distanceMeters, 1.2);
    await service.dispose();
  });

  test('parses the ESP32 132-byte binary sensor frame', () async {
    final service = Esp32BleService();
    final payload = List<int>.filled(132, 0);
    for (var index = 0; index < 64; index++) {
      payload[index * 2] = 0xF0;
      payload[index * 2 + 1] = 0;
    }
    payload[128] = 0xC4;
    payload[129] = 0xFF;
    payload[130] = 1;
    payload[131] = 3;
    final eventFuture = HardwareDataMonitor.instance.events.firstWhere(
      (event) => event.source == 'ThermoCam BLE',
    );

    service.handleNotification(payload);

    final event = await eventFuture.timeout(const Duration(seconds: 1));
    expect(event.scan?.thermalGrid, everyElement(24));
    expect(event.scan?.rssi, -60);
    expect(event.scan?.irDetected, isTrue);
    expect(event.scan?.wifiDeviceCount, 3);
    await service.dispose();
  });
}
