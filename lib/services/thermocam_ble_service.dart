import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;

import '../models/scan_data.dart';

class ThermoCamBleService {
  static const deviceName = 'ThermoCam_BLE';
  static const serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const characteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

  final _scanController = StreamController<ScanData>.broadcast();
  StreamSubscription<List<ble.ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  ble.BluetoothDevice? _device;
  ble.BluetoothCharacteristic? _characteristic;

  Stream<ScanData> get scans => _scanController.stream;

  Future<void> connect() async {
    if (!await ble.FlutterBluePlus.isSupported) {
      throw StateError('此平台不支援 Bluetooth Low Energy');
    }

    final completer = Completer<ble.BluetoothDevice>();
    await _scanSubscription?.cancel();
    _scanSubscription = ble.FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName;
        if (name == deviceName && !completer.isCompleted) {
          completer.complete(result.device);
          break;
        }
      }
    });

    await ble.FlutterBluePlus.startScan(
      withNames: [deviceName],
      timeout: const Duration(seconds: 8),
    );

    try {
      _device = await completer.future.timeout(const Duration(seconds: 8));
    } finally {
      await ble.FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    }

    await _device!.connect(timeout: const Duration(seconds: 10));
    // 熱影像 JSON 大於預設 BLE payload；Android 端先嘗試協商較大 MTU。
    try {
      await _device!.requestMtu(517);
    } on Exception {
      // 某些平台不允許由 App 要求 MTU，仍可繼續使用連線。
    }
    final services = await _device!.discoverServices();
    final service = services.firstWhere(
      (item) => item.uuid == ble.Guid(serviceUuid),
      orElse: () => throw StateError('找不到 ThermoCam BLE Service'),
    );
    _characteristic = service.characteristics.firstWhere(
      (item) => item.uuid == ble.Guid(characteristicUuid),
      orElse: () => throw StateError('找不到 ThermoCam BLE Characteristic'),
    );

    await _characteristic!.setNotifyValue(true);
    await _valueSubscription?.cancel();
    _valueSubscription = _characteristic!.onValueReceived.listen(_handleValue);
  }

  void _handleValue(List<int> value) {
    try {
      final decoded = jsonDecode(utf8.decode(value));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('BLE 資料不是 JSON 物件');
      }
      _scanController.add(
        ScanData.fromHardwareJson(
          decoded,
          deviceId: _device?.remoteId.str ?? 'thermocam',
          deviceName: _device?.platformName.isNotEmpty == true
              ? _device!.platformName
              : deviceName,
        ),
      );
    } on FormatException {
      // 忽略不完整或格式錯誤的單筆通知，等待下一筆完整資料。
    } on JsonUnsupportedObjectError {
      // 忽略不完整或格式錯誤的單筆通知，等待下一筆完整資料。
    }
  }

  Future<void> dispose() async {
    await _valueSubscription?.cancel();
    await _scanSubscription?.cancel();
    await _device?.disconnect();
    await _scanController.close();
  }
}