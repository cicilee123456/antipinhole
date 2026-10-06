import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:flutter_web_bluetooth/flutter_web_bluetooth.dart' as web_ble;
import 'package:http/http.dart' as http;

import '../models/cc1101_diagnostic_sample.dart';

class Cc1101DiagnosticService {
  Cc1101DiagnosticService({
    String baseUrl = 'http://192.168.4.1',
    this.bluetoothDeviceName = 'CC1101_BLE',
    this.bluetoothServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
    this.bluetoothCharacteristicUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
  }) : _endpoint = Uri.parse('$baseUrl/data');

  static const defaultBluetoothDeviceName = 'CC1101_BLE';
  static const defaultBluetoothServiceUuid =
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const defaultBluetoothCharacteristicUuid =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  Uri _endpoint;
  final String bluetoothDeviceName;
  final String bluetoothServiceUuid;
  final String bluetoothCharacteristicUuid;
  final http.Client _client = http.Client();
  final _controller = StreamController<Cc1101DiagnosticSample>.broadcast();
  StreamSubscription<List<ble.ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<ByteData>? _webValueSubscription;
  ble.BluetoothDevice? _bluetoothDevice;
  ble.BluetoothCharacteristic? _bluetoothCharacteristic;
  web_ble.BluetoothDevice? _webDevice;
  web_ble.BluetoothCharacteristic? _webCharacteristic;
  Timer? _timer;
  bool _requestInFlight = false;

  Stream<Cc1101DiagnosticSample> get samples => _controller.stream;

  void updateBaseUrl(String baseUrl) {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'\/+$'), '');
    if (normalized.isEmpty) {
      throw const FormatException('ESP32 IP 或網址不可為空白');
    }
    final uri = Uri.tryParse('$normalized/data');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('ESP32 IP 或網址格式不正確');
    }
    _endpoint = uri;
  }

  Future<void> start({bool bluetooth = false}) async {
    if (_timer != null) return;
    if (bluetooth) {
      await _startBluetooth();
      return;
    }
    await _pollOnce(rethrowError: true);
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_pollOnce()),
    );
  }

  Future<void> _startBluetooth() async {
    if (kIsWeb) {
      await _startWebBluetooth();
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

    final deviceCompleter = Completer<ble.BluetoothDevice>();
    await _scanSubscription?.cancel();
    _scanSubscription = ble.FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName;
        final advertisedName = result.advertisementData.advName;
        if ((name == bluetoothDeviceName ||
                advertisedName == bluetoothDeviceName) &&
            !deviceCompleter.isCompleted) {
          deviceCompleter.complete(result.device);
          break;
        }
      }
    });

    try {
      await ble.FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      _bluetoothDevice = await deviceCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError(
          '找不到 BLE 裝置 $bluetoothDeviceName，請確認裝置已開機且正在廣播',
        ),
      );
    } finally {
      await ble.FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    }

    await _bluetoothDevice!.connect(timeout: const Duration(seconds: 10));
    final services = await _bluetoothDevice!.discoverServices();
    final service = services.firstWhere(
      (item) => item.uuid == ble.Guid(bluetoothServiceUuid),
      orElse: () => throw StateError(
        '找不到 CC1101 BLE Service $bluetoothServiceUuid',
      ),
    );
    _bluetoothCharacteristic = service.characteristics.firstWhere(
      (item) => item.uuid == ble.Guid(bluetoothCharacteristicUuid),
      orElse: () => throw StateError(
        '找不到 CC1101 BLE Characteristic $bluetoothCharacteristicUuid',
      ),
    );

    await _bluetoothCharacteristic!.setNotifyValue(true);
    await _valueSubscription?.cancel();
    _valueSubscription =
        _bluetoothCharacteristic!.onValueReceived.listen(_handleBluetoothValue);
  }

  Future<void> _startWebBluetooth() async {
    final bluetooth = web_ble.FlutterWebBluetooth.instance;
    if (!bluetooth.isBluetoothApiSupported) {
      throw StateError('請使用 HTTPS 的 Chrome 或 Edge 開啟 Web Bluetooth');
    }
    if (!await bluetooth.getAvailability()) {
      throw StateError('找不到可用的藍牙介面，請開啟電腦藍牙');
    }

    _webDevice = await bluetooth.requestDevice(
      web_ble.RequestOptionsBuilder.acceptAllDevices(
        optionalServices: [bluetoothServiceUuid],
      ),
      checkingAvailability: true,
    );
    await _webDevice!.connect(timeout: const Duration(seconds: 10));
    final services = await _webDevice!.discoverServices();
    final service = services.firstWhere(
      (item) => item.uuid.toLowerCase() == bluetoothServiceUuid.toLowerCase(),
      orElse: () => throw StateError(
        '找不到 CC1101 BLE Service $bluetoothServiceUuid',
      ),
    );
    _webCharacteristic =
        await service.getCharacteristic(bluetoothCharacteristicUuid);
    await _webCharacteristic!.startNotifications();
    await _webValueSubscription?.cancel();
    _webValueSubscription = _webCharacteristic!.value.listen((value) {
      _handleBluetoothValue(
        value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
      );
    });
  }

  void _handleBluetoothValue(List<int> value) {
    final text = utf8.decode(value, allowMalformed: false).trim();
    if (text.isEmpty) return;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('CC1101 BLE 回應必須是 JSON 物件');
      }
      _controller.add(Cc1101DiagnosticSample.fromJson(decoded));
    } catch (error, stackTrace) {
      _controller.addError(error, stackTrace);
    }
  }

  Future<void> _pollOnce({bool rethrowError = false}) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    try {
      final response =
          await _client.get(_endpoint).timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) {
        throw StateError('ESP32 HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('ESP32 回應必須是 JSON 物件');
      }
      _controller.add(Cc1101DiagnosticSample.fromJson(decoded));
    } catch (error, stackTrace) {
      _controller.addError(error, stackTrace);
      if (rethrowError) rethrow;
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    await _webValueSubscription?.cancel();
    _webValueSubscription = null;
    await _bluetoothCharacteristic?.setNotifyValue(false);
    await _bluetoothDevice?.disconnect();
    await _webCharacteristic?.stopNotifications();
    _webDevice?.disconnect();
    _bluetoothCharacteristic = null;
    _bluetoothDevice = null;
    _webCharacteristic = null;
    _webDevice = null;
  }

  Future<void> dispose() async {
    await stop();
    _client.close();
    await _controller.close();
  }
}
