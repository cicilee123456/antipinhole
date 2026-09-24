import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/scan_data.dart';
import 'hardware_data_monitor.dart';

class Esp32HttpService {
  Esp32HttpService({String baseUrl = 'http://172.20.10.3'})
      : _endpoint = Uri.parse('$baseUrl/data');

  final Uri _endpoint;
  final http.Client _client = http.Client();
  final _scanController = StreamController<ScanData>.broadcast();
  Timer? _timer;
  bool _pollInFlight = false;

  Stream<ScanData> get scans => _scanController.stream;

  Future<void> start() async {
    if (_timer != null) return;

    late final ScanData firstScan;
    try {
      firstScan = await _fetchScan();
    } catch (error) {
      HardwareDataMonitor.instance.add(
        source: 'ESP32 HTTP',
        rawText: '',
        error: error.toString(),
      );
      rethrow;
    }
    _scanController.add(firstScan);
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_pollOnce()),
    );
  }

  Future<void> _pollOnce() async {
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      _scanController.add(await _fetchScan());
    } catch (error, stackTrace) {
      HardwareDataMonitor.instance.add(
        source: 'ESP32 HTTP',
        rawText: '',
        error: error.toString(),
      );
      _scanController.addError(error, stackTrace);
    } finally {
      _pollInFlight = false;
    }
  }

  Future<ScanData> _fetchScan() async {
    final response = await _client
        .get(_endpoint)
        .timeout(const Duration(seconds: 2));
    if (response.statusCode != 200) {
      throw StateError('ESP32 HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ESP32 回應必須是 JSON 物件');
    }
    try {
      final scan = ScanData.fromEsp32Json(decoded);
      HardwareDataMonitor.instance.add(
        source: 'ESP32 HTTP',
        rawText: response.body,
        scan: scan,
      );
      return scan;
    } on FormatException catch (error) {
      HardwareDataMonitor.instance.add(
        source: 'ESP32 HTTP',
        rawText: response.body,
        error: error.message,
      );
      rethrow;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    await stop();
    _client.close();
    await _scanController.close();
  }
}