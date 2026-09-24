import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart' as web_ble;

import '../models/scan_data.dart';
import 'hardware_data_monitor.dart';

class ThermoCamBleService {
  static const deviceName = 'ThermoCam_BLE';
  static const serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const characteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

  final _scanController = StreamController<ScanData>.broadcast();
  StreamSubscription<List<ble.ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  ble.BluetoothDevice? _device;
  ble.BluetoothCharacteristic? _characteristic;
  web_ble.BluetoothDevice? _webDevice;
  web_ble.BluetoothCharacteristic? _webCharacteristic;
  StreamSubscription<ByteData>? _webValueSubscription;

  Stream<ScanData> get scans => _scanController.stream;

  Future<void> connect() async {
    if (kIsWeb) {
      await _connectWeb();
      return;
    }

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

  Future<void> _connectWeb() async {
    final bluetooth = web_ble.FlutterWebBluetooth.instance;
    if (!bluetooth.isBluetoothApiSupported) {
      throw StateError('目前瀏覽器不支援 Web Bluetooth，請使用 HTTPS 的 Chrome 或 Edge');
    }
    if (!await bluetooth.getAvailability()) {
      throw StateError('找不到可用的藍牙介面，請開啟電腦藍牙');
    }

    _webDevice = await bluetooth.requestDevice(
      web_ble.RequestOptionsBuilder.acceptAllDevices(
        optionalServices: [serviceUuid],
      ),
      checkingAvailability: true,
    );
    await _webDevice!.connect(timeout: const Duration(seconds: 10));
    final services = await _webDevice!.discoverServices();
    final service = services.firstWhere(
      (item) => item.uuid.toLowerCase() == serviceUuid,
      orElse: () => throw StateError('找不到 ThermoCam BLE Service'),
    );
    _webCharacteristic = await service.getCharacteristic(characteristicUuid);
    await _webCharacteristic!.startNotifications();
    await _webValueSubscription?.cancel();
    _webValueSubscription = _webCharacteristic!.value.listen((value) {
      _handleValue(
        value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
        deviceId: _webDevice!.id,
        deviceName: _webDevice!.name?.isNotEmpty == true
            ? _webDevice!.name!
            : deviceName,
      );
    });
  }

  void _handleValue(
    List<int> value, {
    String? deviceId,
    String? deviceName,
  }) {
    final rawText = utf8.decode(value, allowMalformed: true);
    try {
      final decoded = jsonDecode(rawText);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('BLE 資料不是 JSON 物件');
      }
      final scan = ScanData.fromHardwareJson(
        decoded,
        deviceId: deviceId ?? _device?.remoteId.str ?? 'thermocam',
        deviceName: deviceName ?? (_device?.platformName.isNotEmpty == true
            ? _device!.platformName
            : ThermoCamBleService.deviceName),
      );
      HardwareDataMonitor.instance.add(
        source: 'BLE',
        rawText: rawText,
        scan: scan,
      );
      _scanController.add(scan);
    } on FormatException {
      HardwareDataMonitor.instance.add(
        source: 'BLE',
        rawText: rawText,
        error: 'JSON 格式或欄位解析失敗',
      );
      // 忽略不完整或格式錯誤的單筆通知，等待下一筆完整資料。
    } on JsonUnsupportedObjectError {
      HardwareDataMonitor.instance.add(
        source: 'BLE',
        rawText: rawText,
        error: 'JSON 格式或欄位解析失敗',
      );
      // 忽略不完整或格式錯誤的單筆通知，等待下一筆完整資料。
    }
  }

  Future<void> dispose() async {
    await _valueSubscription?.cancel();
    await _scanSubscription?.cancel();
    await _webValueSubscription?.cancel();
    await _webCharacteristic?.stopNotifications();
    _webDevice?.disconnect();
    await _device?.disconnect();
    await _scanController.close();
  }
}