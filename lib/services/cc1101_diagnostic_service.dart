import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/cc1101_diagnostic_sample.dart';

class Cc1101DiagnosticService {
  Cc1101DiagnosticService({String baseUrl = 'http://192.168.4.1'})
      : _endpoint = Uri.parse('$baseUrl/data');

  final Uri _endpoint;
  final http.Client _client = http.Client();
  final _controller = StreamController<Cc1101DiagnosticSample>.broadcast();
  Timer? _timer;
  bool _requestInFlight = false;

  Stream<Cc1101DiagnosticSample> get samples => _controller.stream;

  Future<void> start() async {
    if (_timer != null) return;
    await _pollOnce();
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_pollOnce()),
    );
  }

  Future<void> _pollOnce() async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    try {
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
      _controller.add(Cc1101DiagnosticSample.fromJson(decoded));
    } catch (error, stackTrace) {
      _controller.addError(error, stackTrace);
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    await stop();
    _client.close();
    await _controller.close();
  }
}
