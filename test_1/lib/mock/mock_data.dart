// ============================================================
// mock_data.dart
// ------------------------------------------------------------
// 提供 3 組符合李雅淳規格的 Mock 資料(安全 / 針孔高溫+RF / 環境誤報),
// 讓葉孟宣可以在李雅淳、彭同學的部分還沒整合進來前,
// 獨立測試熱圖渲染、風險判斷、資料庫寫入是否正常運作。
//
// 判斷規則(李雅淳提供):
//   高風險: ΔT >= 6.0°C 且 RSSI >= -50 dBm
//   注意:  ΔT >= 4.0°C 或 RSSI >= -65 dBm
//   安全:  其餘情況
// ============================================================

import 'dart:math';

class MockScenario {
  final String name;
  final Map<String, dynamic> json;
  MockScenario(this.name, this.json);
}

/// 產生一組「安全」情境:溫度均勻分布在室溫附近,沒有明顯熱點,RSSI 也弱
Map<String, dynamic> _buildSafeScenario() {
  final rand = Random(1);
  final pixels = List.generate(
    64,
    (i) => 24.0 + rand.nextDouble() * 1.0, // 24.0 ~ 25.0°C,均勻室溫
  );
  return {
    'pixels': pixels,
    'rssi': -75.0, // 訊號弱,符合「安全」情境
  };
}

/// 產生一組「針孔高溫 + RF 訊號強」情境:中央有明顯熱點,且 RSSI 很強
/// ΔT 預期 >= 6.0°C,RSSI >= -50 dBm,對應「高風險」判斷
Map<String, dynamic> _buildHighRiskScenario() {
  final pixels = List.filled(64, 24.5);
  // 在 8x8 網格中央附近(index 27, 28, 35, 36)製造一個明顯熱點
  // 模擬「1x1 cm 微型鏡頭電路」的異常發熱特徵
  const hotIndices = [27, 28, 35, 36];
  for (final idx in hotIndices) {
    pixels[idx] = 32.0; // 明顯高於周圍室溫,ΔT 會超過 6°C
  }
  return {
    'pixels': pixels,
    'rssi': -42.0, // 訊號強,符合「高風險」情境
  };
}

/// 產生一組「環境誤報」情境:有溫度異常(例如電燈、家電發熱),
/// 但 RSSI 不強,用來測試系統不會誤判成高風險,只會落在「注意」等級
Map<String, dynamic> _buildFalsePositiveScenario() {
  final pixels = List.filled(64, 24.0);
  const warmIndices = [10, 11, 18, 19];
  for (final idx in warmIndices) {
    pixels[idx] = 29.5; // ΔT 大約 4~5°C,達到「注意」但不到「高風險」門檻
  }
  return {
    'pixels': pixels,
    'rssi': -70.0, // 訊號弱,不會被判定為高風險
  };
}

final List<MockScenario> mockScenarios = [
  MockScenario('安全情境', _buildSafeScenario()),
  MockScenario('針孔高風險情境', _buildHighRiskScenario()),
  MockScenario('環境誤報情境', _buildFalsePositiveScenario()),
];