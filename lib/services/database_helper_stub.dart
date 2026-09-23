import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/detection_record.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static const _storageKey = 'detection_records';

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  Future<int> insertRecord(DetectionRecord record) async {
    final preferences = await _preferences;
    final records = await getAllRecords();
    records.removeWhere((item) => item.timestamp == record.timestamp);
    records.add(record);
    await preferences.setString(
      _storageKey,
      jsonEncode(records.map((item) => item.toMap()).toList()),
    );
    return record.id ?? records.length;
  }

  Future<List<DetectionRecord>> getAllRecords() async {
    final raw = (await _preferences).getString(_storageKey);
    if (raw == null) return [];
    final records = (jsonDecode(raw) as List)
        .map((item) => DetectionRecord.fromMap(Map<String, Object?>.from(item)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return records;
  }

  Future<void> close() async {}
}