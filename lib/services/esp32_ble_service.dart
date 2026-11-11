import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart' as web_ble;

import '../models/cc1101_diagnostic_sample.dart';
import 'hardware_data_monitor.dart';

class Esp32BleService {
  static const deviceName = 'CC1101_BLE';
  static const serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const characteristicUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  StreamSubscription<List<ble.ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  ble.BluetoothDevice? _device;
  ble.BluetoothCharacteristic? _characteristic;
  web_ble.BluetoothDevice? _webDevice;
  web_ble.BluetoothCharacteristic? _webCharacteristic;
  StreamSubscription<ByteData>? _webValueSubscription;
  String _jsonBuffer = '';

  bool get supportsRssi => !kIsWeb;

  Future<int> readRssi() async {
    if (kIsWeb) {
      throw UnsupportedError('Web Bluetooth 不提供 BLE RSSI 讀取 API');
    }
    final device = _device;
    if (device == null) throw StateError('ESP32 BLE 尚未連線');
    return device.readRssi();
  }

  Future<void> connect() async {
    if (kIsWeb) {
      await _connectWeb();
      return;
    }

    if (!await ble.FlutterBluePlus.isSupported) {
      throw StateError('此平台不支援 Bluetooth Low Energy');
    }

    try {
      await ble.FlutterBluePlus.turnOn();
    } on Exception {
      // iOS and some Android versions do not allow the app to enable Bluetooth.
    }
    final adapterState = await ble.FlutterBluePlus.adapterState.first;
    if (adapterState != ble.BluetoothAdapterState.on) {
      throw StateError('請開啟手機藍牙，並允許 App 使用附近裝置');
    }

    final completer = Completer<ble.BluetoothDevice>();
    await _scanSubscription?.cancel();
    _scanSubscription = ble.FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final deviceName = result.device.platformName;
        final advertisedName = result.advertisementData.advName;
        if ((deviceName == Esp32BleService.deviceName ||
                advertisedName == Esp32BleService.deviceName) &&
            !completer.isCompleted) {
          completer.complete(result.device);
          break;
        }
      }
    });

    try {
      await ble.FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      _device = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError(
          '找不到 BLE 裝置 $deviceName，請確認裝置已開機且正在廣播',
        ),
      );
    } finally {
      await ble.FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    }

    await _device!.connect(timeout: const Duration(seconds: 10));
    // 協商較大的 MTU，避免診斷 JSON 被限制在預設 ATT payload 大小。
    try {
      await _device!.requestMtu(517);
    } on Exception {
      // 某些平台不允許由 App 要求 MTU，仍可繼續使用連線。
    }
    final services = await _device!.discoverServices();
    final service = services.firstWhere(
      (item) => item.uuid == ble.Guid(serviceUuid),
      orElse: () => throw StateError('找不到 CC1101 BLE Service $serviceUuid'),
    );
    _characteristic = service.characteristics.firstWhere(
      (item) => item.uuid == ble.Guid(characteristicUuid),
      orElse: () =>
          throw StateError('找不到 CC1101 BLE Characteristic $characteristicUuid'),
    );

    await _characteristic!.setNotifyValue(true);
    await _valueSubscription?.cancel();
    _valueSubscription =
        _characteristic!.onValueReceived.listen(handleNotification);
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
      (item) => item.uuid.toLowerCase() == serviceUuid.toLowerCase(),
      orElse: () => throw StateError('找不到 CC1101 BLE Service $serviceUuid'),
    );
    _webCharacteristic = await service.getCharacteristic(characteristicUuid);
    await _webCharacteristic!.startNotifications();
    await _webValueSubscription?.cancel();
    _webValueSubscription = _webCharacteristic!.value.listen((value) {
      handleNotification(
        value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
      );
    });
  }

  @visibleForTesting
  void handleNotification(List<int> value) {
    var rawText = '';
    try {
      rawText = utf8.decode(value, allowMalformed: false);
      _jsonBuffer += rawText;
      if (_jsonBuffer.length > 4096) {
        _jsonBuffer = '';
        throw const FormatException('CC1101 BLE JSON 封包超過 4096 字元');
      }

      while (true) {
        final start = _jsonBuffer.indexOf('{');
        if (start < 0) {
          _jsonBuffer = '';
          return;
        }
        if (start > 0) _jsonBuffer = _jsonBuffer.substring(start);

        var depth = 0;
        var end = -1;
        for (var index = 0; index < _jsonBuffer.length; index++) {
          final character = _jsonBuffer.codeUnitAt(index);
          if (character == 123) depth++;
          if (character == 125 && --depth == 0) {
            end = index + 1;
            break;
          }
        }
        if (end < 0) return;

        final jsonText = _jsonBuffer.substring(0, end);
        _jsonBuffer = _jsonBuffer.substring(end);
        final decoded = jsonDecode(jsonText);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('CC1101 BLE 回應必須是 JSON 物件');
        }
        final sample = Cc1101DiagnosticSample.fromJson(decoded);
        HardwareDataMonitor.instance.add(
          source: 'CC1101 BLE',
          rawText: jsonText,
          cc1101Sample: sample,
        );
      }
    } on FormatException catch (error) {
      final invalidPayload = _jsonBuffer.isEmpty
          ? (rawText.isEmpty ? String.fromCharCodes(value) : rawText)
          : _jsonBuffer;
      _jsonBuffer = '';
      HardwareDataMonitor.instance.add(
        source: 'CC1101 BLE',
        rawText: invalidPayload,
        error: error.message,
      );
    } on JsonUnsupportedObjectError catch (error) {
      final invalidPayload = _jsonBuffer.isEmpty
          ? (rawText.isEmpty ? String.fromCharCodes(value) : rawText)
          : _jsonBuffer;
      _jsonBuffer = '';
      HardwareDataMonitor.instance.add(
        source: 'CC1101 BLE',
        rawText: invalidPayload,
        error: error.toString(),
      );
    }
  }

  Future<void> disconnect() async {
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _webValueSubscription?.cancel();
    _webValueSubscription = null;
    await _webCharacteristic?.stopNotifications();
    _webCharacteristic = null;
    _webDevice?.disconnect();
    _webDevice = null;
    await _device?.disconnect();
    _device = null;
    _characteristic = null;
    _jsonBuffer = '';
  }

  Future<void> dispose() async {
    await disconnect();
  }
}
