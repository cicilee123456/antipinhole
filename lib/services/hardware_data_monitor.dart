import 'dart:async';

import '../models/scan_data.dart';
import '../models/cc1101_diagnostic_sample.dart';

class HardwareDataEvent {
  const HardwareDataEvent({
    required this.timestamp,
    required this.source,
    required this.rawText,
    this.scan,
    this.cc1101,
    this.error,
  });

  final DateTime timestamp;
  final String source;
  final String rawText;
  final ScanData? scan;
  final Cc1101DiagnosticSample? cc1101;
  final String? error;

  bool get isParsed => (scan != null || cc1101 != null) && error == null;
}

class HardwareDataMonitor {
  HardwareDataMonitor._();

  static final instance = HardwareDataMonitor._();
  final _controller = StreamController<HardwareDataEvent>.broadcast();

  Stream<HardwareDataEvent> get events => _controller.stream;

  void add({
    required String source,
    required String rawText,
    ScanData? scan,
    Cc1101DiagnosticSample? cc1101,
    String? error,
  }) {
    if (!_controller.isClosed) {
      _controller.add(
        HardwareDataEvent(
          timestamp: DateTime.now(),
          source: source,
          rawText: rawText,
          scan: scan,
          cc1101: cc1101,
          error: error,
        ),
      );
    }
  }
}
