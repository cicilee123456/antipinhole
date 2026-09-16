import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/scan_data.dart';

// 載入固定 JSON 情境，提供安全、警示與高風險測試資料。
class MockDataService {
  const MockDataService();

  static const scenarioAssets = <String, String>{
    'safe': 'assets/scenario_safe.json',
    'danger': 'assets/scenario_danger.json',
    'warning': 'assets/scenario_warning.json',
  };

  Future<ScanData> loadScenario(String scenarioKey) async {
    final assetPath = scenarioAssets[scenarioKey];
    if (assetPath == null) {
      throw ArgumentError.value(scenarioKey, 'scenarioKey', '未知情境');
    }

    final rawJson = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('情境 JSON 根節點必須是物件');
    }

    return ScanData.fromJson(decoded);
  }
}