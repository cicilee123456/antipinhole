import 'dart:async';

import '../models/cc1101_diagnostic_sample.dart';
import '../models/scan_data.dart';

class HardwareDataEvent {
  const HardwareDataEvent({
    required this.timestamp,
    required this.source,
    required this.rawText,
    this.scan,
    this.cc1101Sample,
    this.error,
  });

  final DateTime timestamp;
  final String source;
  final String rawText;
  final ScanData? scan;
  final Cc1101DiagnosticSample? cc1101Sample;
  final String? error;

  bool get isParsed => (scan != null || cc1101Sample != null) && error == null;
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
    Cc1101DiagnosticSample? cc1101Sample,
    String? error,
  }) {
    if (!_controller.isClosed) {
      _controller.add(
        HardwareDataEvent(
          timestamp: DateTime.now(),
          source: source,
          rawText: rawText,
          scan: scan,
          cc1101Sample: cc1101Sample,
          error: error,
        ),
      );
    }
  }
}
