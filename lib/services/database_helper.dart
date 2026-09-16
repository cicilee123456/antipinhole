import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/detection_record.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static const _databaseName = 'anti_pinhole.db';
  static const _databaseVersion = 1;
  static const tableName = 'detection_records';

  Database? _database;
  final List<DetectionRecord> _webRecords = <DetectionRecord>[];
  int _nextWebId = 1;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final databasesPath = await getDatabasesPath();
    _database = await openDatabase(
      join(databasesPath, _databaseName),
      version: _databaseVersion,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE $tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            maxDeltaT REAL NOT NULL,
            maxRSSI REAL NOT NULL,
            latitude REAL,
            longitude REAL,
            statusColor TEXT NOT NULL CHECK(statusColor IN ('RED', 'YELLOW')),
            userDecision TEXT NOT NULL CHECK(userDecision IN ('CONFIRMED_DANGER', 'UNCERTAIN_WARNING')),
            adviceText TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<int> insertRecord(DetectionRecord record) async {
    if (kIsWeb) {
      final id = record.id ?? _nextWebId++;
      _webRecords.add(
        DetectionRecord(
          id: id,
          timestamp: record.timestamp,
          maxDeltaT: record.maxDeltaT,
          maxRSSI: record.maxRSSI,
          latitude: record.latitude,
          longitude: record.longitude,
          statusColor: record.statusColor,
          userDecision: record.userDecision,
          adviceText: record.adviceText,
        ),
      );
      return id;
    }

    final database = await this.database;
    return database.insert(tableName, record.toMap());
  }

  Future<List<DetectionRecord>> getAllRecords() async {
    if (kIsWeb) {
      final records = List<DetectionRecord>.of(_webRecords)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return List<DetectionRecord>.unmodifiable(records);
    }

    final database = await this.database;
    final rows = await database.query(tableName, orderBy: 'timestamp DESC');
    return rows.map(DetectionRecord.fromMap).toList(growable: false);
  }
}