import 'dart:async';

import '../models/detection_record.dart';

class RecordChangeNotifier {
  RecordChangeNotifier._();

  static final instance = RecordChangeNotifier._();
  final _controller = StreamController<DetectionRecord>.broadcast();

  Stream<DetectionRecord> get changes => _controller.stream;

  void notify(DetectionRecord record) {
    if (!_controller.isClosed) _controller.add(record);
  }
}