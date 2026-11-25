import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart' as web_ble;
import 'package:permission_handler/permission_handler.dart';

import '../models/cc1101_diagnostic_sample.dart';
import '../models/scan_data.dart';
import 'hardware_data_monitor.dart';

class Esp32BleService {
  static const deviceName = 'CC1101_BLE';
  static const serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const characteristicUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const thermoCamDeviceName = 'ThermoCam_BLE';
  static const thermoCamServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const thermoCamCharacteristicUuid =
      'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const wifiListCharacteristicUuid =
      'beb5483e-36e1-4688-b7f5-ea07361b26a9';
  static const _binarySensorPayloadLength = 132;

  StreamSubscription<List<ble.ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<List<int>>? _wifiValueSubscription;
  ble.BluetoothDevice? _device;
  ble.BluetoothCharacteristic? _characteristic;
  ble.BluetoothCharacteristic? _wifiCharacteristic;
  web_ble.BluetoothDevice? _webDevice;
  web_ble.BluetoothCharacteristic? _webCharacteristic;
  web_ble.BluetoothCharacteristic? _webWifiCharacteristic;
  StreamSubscription<ByteData>? _webValueSubscription;
  StreamSubscription<ByteData>? _webWifiValueSubscription;
  final List<int> _jsonBuffer = [];
  List<WifiAccessPoint>? _pendingWifiNetworks;

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

    await _requestAndroidBlePermissions();

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
        if ((_supportedDeviceNames.contains(deviceName) ||
                _supportedDeviceNames.contains(advertisedName)) &&
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
          '找不到 BLE 裝置 $deviceName 或 $thermoCamDeviceName，'
          '請確認裝置已開機且正在廣播',
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
      (item) =>
          _supportedServiceUuids.contains(item.uuid.toString().toLowerCase()),
      orElse: () => throw StateError(
        '找不到支援的 ESP32 BLE Service（$serviceUuid 或 $thermoCamServiceUuid）',
      ),
    );
    _characteristic = service.characteristics.firstWhere(
      (item) => _supportedCharacteristicUuids
          .contains(item.uuid.toString().toLowerCase()),
      orElse: () => throw StateError(
        '找不到支援的 ESP32 BLE Characteristic',
      ),
    );

    final wifiCharacteristic = service.characteristics.where(
      (item) =>
          item.uuid.toString().toLowerCase() == wifiListCharacteristicUuid,
    );
    if (wifiCharacteristic.isNotEmpty) {
      _wifiCharacteristic = wifiCharacteristic.first;
    }

    await _characteristic!.setNotifyValue(true);
    await _valueSubscription?.cancel();
    _valueSubscription =
        _characteristic!.onValueReceived.listen(handleNotification);
    if (_wifiCharacteristic != null) {
      await _wifiCharacteristic!.setNotifyValue(true);
      await _wifiValueSubscription?.cancel();
      _wifiValueSubscription = _wifiCharacteristic!.onValueReceived
          .listen(handleWifiListNotification);
    }
  }

  Future<void> _requestAndroidBlePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final permissions = sdkInt >= 31
        ? [Permission.bluetoothScan, Permission.bluetoothConnect]
        : [Permission.locationWhenInUse];
    final statuses = await permissions.request();
    if (statuses.values.every((status) => status.isGranted)) return;

    throw StateError(
      sdkInt >= 31
          ? '請允許 App 使用「附近裝置」權限後再連線'
          : '請允許 App 使用定位權限；Android 11 以下掃描 BLE 需要此權限',
    );
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
        optionalServices: [serviceUuid, thermoCamServiceUuid],
      ),
      checkingAvailability: true,
    );
    await _webDevice!.connect(timeout: const Duration(seconds: 10));
    final services = await _webDevice!.discoverServices();
    final service = services.firstWhere(
      (item) => _supportedServiceUuids.contains(item.uuid.toLowerCase()),
      orElse: () => throw StateError(
        '找不到支援的 ESP32 BLE Service（$serviceUuid 或 $thermoCamServiceUuid）',
      ),
    );
    final characteristicUuid =
        service.uuid.toLowerCase() == thermoCamServiceUuid
            ? thermoCamCharacteristicUuid
            : Esp32BleService.characteristicUuid;
    _webCharacteristic = await service.getCharacteristic(characteristicUuid);
    await _webCharacteristic!.startNotifications();
    await _webValueSubscription?.cancel();
    _webValueSubscription = _webCharacteristic!.value.listen((value) {
      handleNotification(
        value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
      );
    });

    if (service.uuid.toLowerCase() == thermoCamServiceUuid) {
      try {
        _webWifiCharacteristic =
            await service.getCharacteristic(wifiListCharacteristicUuid);
      } on web_ble.NotFoundError {
        _webWifiCharacteristic = null;
      }
      if (_webWifiCharacteristic != null) {
        await _webWifiCharacteristic!.startNotifications();
        await _webWifiValueSubscription?.cancel();
        _webWifiValueSubscription =
            _webWifiCharacteristic!.value.listen((value) {
          handleWifiListNotification(
            value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
          );
        });
      }
    }
  }

  @visibleForTesting
  void handleWifiListNotification(List<int> value) {
    try {
      final message = utf8.decode(value, allowMalformed: false);
      final controlMessage = message.trim();
      if (controlMessage == 'START') {
        _pendingWifiNetworks = [];
        return;
      }
      if (controlMessage == 'END') {
        final networks = _pendingWifiNetworks;
        if (networks == null) {
          throw const FormatException('收到 Wi-Fi END，但沒有對應的 START');
        }
        _pendingWifiNetworks = null;
        HardwareDataMonitor.instance.add(
          source: 'Wi-Fi BLE',
          rawText: 'Wi-Fi AP 清單完成（${networks.length} 筆）',
          wifiNetworks: List.unmodifiable(networks),
        );
        return;
      }

      final networks = _pendingWifiNetworks;
      if (networks == null) {
        throw const FormatException('收到 Wi-Fi 資料列，但不在 START/END 清單內');
      }

      final firstComma = message.indexOf(',');
      final secondComma =
          firstComma < 0 ? -1 : message.indexOf(',', firstComma + 1);
      if (firstComma <= 0 || secondComma < 0) {
        throw const FormatException(
          'Wi-Fi 資料列格式錯誤，預期為 rssi,distance,ssid',
        );
      }
      final rssi = int.tryParse(message.substring(0, firstComma).trim());
      final distance = double.tryParse(
          message.substring(firstComma + 1, secondComma).trim());
      if (rssi == null || distance == null) {
        throw const FormatException('Wi-Fi RSSI 或距離不是有效數值');
      }

      networks.add(
        WifiAccessPoint(
          ssid: message.substring(secondComma + 1).isEmpty
              ? '[Hidden SSID]'
              : message.substring(secondComma + 1),
          rssi: rssi.toDouble(),
          distanceMeters: distance,
        ),
      );
    } on FormatException catch (error) {
      HardwareDataMonitor.instance.add(
        source: 'Wi-Fi BLE',
        rawText: 'Wi-Fi 清單通知無法解析',
        error: error.message,
      );
    }
  }

  @visibleForTesting
  void handleNotification(List<int> value) {
    final isBinarySensorFrame =
        value.length == _binarySensorPayloadLength && value[130] <= 1;
    if (_jsonBuffer.isEmpty && isBinarySensorFrame) {
      _handleBinaryNotification(value);
      return;
    }

    try {
      _jsonBuffer.addAll(value);
      if (_jsonBuffer.length > 16384) {
        _jsonBuffer.clear();
        throw const FormatException('ESP32 BLE JSON 封包超過 16384 bytes');
      }

      while (true) {
        final start = _jsonBuffer.indexOf(0x7B);
        if (start < 0) {
          _jsonBuffer.clear();
          return;
        }
        if (start > 0) _jsonBuffer.removeRange(0, start);

        var depth = 0;
        var end = -1;
        var inString = false;
        var escaped = false;
        for (var index = 0; index < _jsonBuffer.length; index++) {
          final character = _jsonBuffer[index];
          if (inString) {
            if (escaped) {
              escaped = false;
            } else if (character == 0x5C) {
              escaped = true;
            } else if (character == 0x22) {
              inString = false;
            }
            continue;
          }
          if (character == 0x22) inString = true;
          if (character == 0x7B) depth++;
          if (character == 0x7D && --depth == 0) {
            end = index + 1;
            break;
          }
        }
        if (end < 0) return;

        final jsonBytes = _jsonBuffer.sublist(0, end);
        _jsonBuffer.removeRange(0, end);
        final jsonText = utf8.decode(jsonBytes, allowMalformed: false);
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
          ? String.fromCharCodes(value)
          : String.fromCharCodes(_jsonBuffer);
      _jsonBuffer.clear();
      HardwareDataMonitor.instance.add(
        source: 'CC1101 BLE',
        rawText: invalidPayload,
        error: error.message,
      );
    } on JsonUnsupportedObjectError catch (error) {
      final invalidPayload = _jsonBuffer.isEmpty
          ? String.fromCharCodes(value)
          : String.fromCharCodes(_jsonBuffer);
      _jsonBuffer.clear();
      HardwareDataMonitor.instance.add(
        source: 'CC1101 BLE',
        rawText: invalidPayload,
        error: error.toString(),
      );
    }
  }

  void _handleBinaryNotification(List<int> value) {
    try {
      final scan = ScanData.fromHardwareBinary(
        value,
        deviceId: thermoCamDeviceName,
        deviceName: thermoCamDeviceName,
      );
      HardwareDataMonitor.instance.add(
        source: 'ThermoCam BLE',
        rawText: '二進位感測封包（${value.length} bytes）',
        scan: scan,
      );
    } on FormatException catch (error) {
      HardwareDataMonitor.instance.add(
        source: 'ThermoCam BLE',
        rawText: '二進位封包（${value.length} bytes）',
        error: error.message,
      );
    }
  }

  Future<void> disconnect() async {
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    await _wifiValueSubscription?.cancel();
    _wifiValueSubscription = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _webValueSubscription?.cancel();
    _webValueSubscription = null;
    await _webWifiValueSubscription?.cancel();
    _webWifiValueSubscription = null;
    await _webCharacteristic?.stopNotifications();
    _webCharacteristic = null;
    await _webWifiCharacteristic?.stopNotifications();
    _webWifiCharacteristic = null;
    _webDevice?.disconnect();
    _webDevice = null;
    await _device?.disconnect();
    _device = null;
    _characteristic = null;
    _jsonBuffer.clear();
    _pendingWifiNetworks = null;
  }

  Future<void> dispose() async {
    await disconnect();
  }

  static const _supportedDeviceNames = {
    deviceName,
    thermoCamDeviceName,
  };
  static const _supportedServiceUuids = {
    serviceUuid,
    thermoCamServiceUuid,
  };
  static const _supportedCharacteristicUuids = {
    characteristicUuid,
    thermoCamCharacteristicUuid,
  };
}
