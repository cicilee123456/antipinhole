import 'package:sqflite/sqflite.dart';

import '../models/detection_record.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static const _databaseName = 'anti_pinhole.db';
  static const _databaseVersion = 1;
  static const tableName = 'detection_records';

  Database? _database;

  Future<Database> get database async {
    final existingDatabase = _database;
    if (existingDatabase != null) return existingDatabase;

    final databasePath = await getDatabasesPath();
    _database = await openDatabase(
      '$databasePath/$_databaseName',
      version: _databaseVersion,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE $tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            maxDeltaT REAL NOT NULL,
            maxRSSI REAL NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            statusColor TEXT NOT NULL CHECK (statusColor IN ('RED', 'YELLOW')),
            userDecision TEXT NOT NULL CHECK (
              userDecision IN ('CONFIRMED_DANGER', 'UNCERTAIN_WARNING')
            ),
            adviceText TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<int> insertRecord(DetectionRecord record) async {
    return (await database).insert(
      tableName,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DetectionRecord>> getAllRecords() async {
    final rows = await (await database).query(tableName, orderBy: 'timestamp DESC');
    return rows.map(DetectionRecord.fromMap).toList(growable: false);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}