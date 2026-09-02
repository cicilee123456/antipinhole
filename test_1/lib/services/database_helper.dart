// ============================================================
// database_helper.dart
// ------------------------------------------------------------
// 負責:
//   建立並操作本機 SQLite 資料庫,記錄高風險事件
//   (時間戳記、ΔT、假 GPS 座標)
//
// 需要在 pubspec.yaml 加入的套件:
//   sqflite: ^2.3.0
//   path: ^1.9.0
//
// 【重點筆記 / 學到的東西】
// - sqflite 是 Flutter 最常用的本機 SQLite 套件,操作模式是
//   「取得資料庫實例(單例) -> 用 SQL 字串操作」,跟一般後端
//   資料庫開發的邏輯很像。
// - 用「單例模式(Singleton)」讓整個 App 共用同一個資料庫連線,
//   避免到處 new 出很多個連線物件造成資源浪費或資料不同步。
// - insert() 回傳自動產生的 id,可以用來確認寫入是否成功。
// ============================================================

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class RiskEvent {
  final int? id;
  final DateTime timestamp;
  final double deltaT;
  final double latitude;
  final double longitude;
  final String riskLabel; // 例如 "高風險"

  RiskEvent({
    this.id,
    required this.timestamp,
    required this.deltaT,
    required this.latitude,
    required this.longitude,
    required this.riskLabel,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'deltaT': deltaT,
      'latitude': latitude,
      'longitude': longitude,
      'riskLabel': riskLabel,
    };
  }

  factory RiskEvent.fromMap(Map<String, dynamic> map) {
    return RiskEvent(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      deltaT: (map['deltaT'] as num).toDouble(),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      riskLabel: map['riskLabel'] as String,
    );
  }
}

class DatabaseHelper {
  // 單例模式:整個 App 共用同一個 DatabaseHelper 實例
  static final DatabaseHelper instance = DatabaseHelper._internal();
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final String path = join(await getDatabasesPath(), 'risk_events.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE risk_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            deltaT REAL NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            riskLabel TEXT NOT NULL
          )
        ''');
      },
    );
  }

  /// 新增一筆風險事件,回傳自動產生的 id
  Future<int> insertRiskEvent(RiskEvent event) async {
    final db = await database;
    return await db.insert(
      'risk_events',
      event.toMap()..remove('id'), // id 是自動遞增,新增時不用帶
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 取得所有風險事件,依時間新到舊排序(方便地圖 / 紀錄頁面顯示)
  Future<List<RiskEvent>> getAllRiskEvents() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'risk_events',
      orderBy: 'timestamp DESC',
    );
    return maps.map((m) => RiskEvent.fromMap(m)).toList();
  }

  /// 清空所有紀錄(測試用,方便重複測試不用一直累積髒資料)
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('risk_events');
  }

  /// 刪除單筆風險事件(依 id)
  Future<void> deleteRiskEvent(int id) async {
    final db = await database;
    await db.delete(
      'risk_events',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 【防重複回報核心邏輯】
  /// 檢查「相近位置 + 相近時間」是否已經有紀錄,避免同一個熱點被重複寫入。
  ///
  /// 判斷條件(可依實測情況調整):
  ///   - 位置相近:經緯度誤差在 distanceThresholdMeters 公尺內
  ///     (這裡用簡化版的度數差直接換算,不是精確的地理距離公式,
  ///      但對於「同一個房間/同一個熱點」這種近距離判斷已經足夠)
  ///   - 時間相近:在 timeWindowMinutes 分鐘內
  ///
  /// 回傳值:如果找到符合條件的既有紀錄,回傳該筆 RiskEvent;
  ///        找不到就回傳 null,代表可以放心新增。
  Future<RiskEvent?> findNearbyRecentEvent({
    required double latitude,
    required double longitude,
    double distanceThresholdMeters = 15.0,
    int timeWindowMinutes = 10,
  }) async {
    final events = await getAllRiskEvents();
    final now = DateTime.now();

    // 緯度 1 度約等於 111,000 公尺,經度會隨緯度縮小,但在校園/住宅這種
    // 小範圍場景下,直接用緯度的換算比例概略估算即可,不需要用到
    // Haversine 公式等更精確但更複雜的計算方式
    const double metersPerDegree = 111000.0;
    final double thresholdDegrees = distanceThresholdMeters / metersPerDegree;

    for (final e in events) {
      final bool isRecentEnough =
          now.difference(e.timestamp).inMinutes.abs() <= timeWindowMinutes;
      final bool isCloseEnough =
          (e.latitude - latitude).abs() <= thresholdDegrees &&
              (e.longitude - longitude).abs() <= thresholdDegrees;

      if (isRecentEnough && isCloseEnough) {
        return e; // 找到相近的既有紀錄,不需要再新增
      }
    }
    return null; // 沒有找到,可以安心新增
  }
}