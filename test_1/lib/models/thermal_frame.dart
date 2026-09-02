// ============================================================
// thermal_frame.dart
// ------------------------------------------------------------
// 負責:
//   1. 定義單筆感測資料的資料結構(對應李雅淳提供的 Mock JSON 格式)
//   2. 實作 8x8 -> 24x24 雙線性插值(Bilinear Interpolation)
//   3. 依李雅淳提供的加權算式,判斷風險等級
//
// 【重點筆記 / 學到的東西】
// - 雙線性插值的核心概念:把低解析度網格(8x8)當成連續的座標
//   平面,對目標高解析度網格(24x24)上的每一個點,回推它在原始
//   8x8 網格中對應的浮點座標,再用旁邊 4 個點做加權平均。
// - 放大倍率 = 24 / 8 = 3,所以 24x24 的每個格子,對應到原始
//   8x8 網格上「非整數」的座標,這就是為什麼需要插值而不能直接
//   拉伸(直接拉伸會出現一格一格的鋸齒,失去平滑感)。
// ============================================================
 
import 'dart:math';
 
/// 風險等級,對應李雅淳提供的三段式判斷
enum RiskLevel { safe, warning, highRisk }
 
class ThermalFrame {
  /// 原始 8x8 = 64 筆溫度資料(攝氏),由 ESP32 BLE 傳來或 Mock JSON 提供
  final List<double> rawPixels; // length = 64
  final double rssi; // 訊號強度 (dBm)
  final DateTime timestamp;
 
  ThermalFrame({
    required this.rawPixels,
    required this.rssi,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
 
  /// 從 Mock JSON / BLE 解析後的 Map 建立物件
  /// 預期 JSON 格式:
  /// {
  ///   "pixels": [24.1, 24.3, ... (64 個數字)],
  ///   "rssi": -48.0
  /// }
  factory ThermalFrame.fromJson(Map<String, dynamic> json) {
    final rawList = (json['pixels'] as List)
        .map((e) => (e as num).toDouble())
        .toList();
    if (rawList.length != 64) {
      throw ArgumentError(
          '溫度資料長度不正確,預期 64 筆,實際 ${rawList.length} 筆');
    }
    return ThermalFrame(
      rawPixels: rawList,
      rssi: (json['rssi'] as num).toDouble(),
    );
  }
 
  /// 取得目前畫面中的最高溫,以及與周圍平均溫度的差值 ΔT
  /// ΔT 定義:最高溫 - 全場平均溫(這是最直觀、常見的定義方式,
  /// 之後如果李雅淳的演算法有更精確的定義,只要換這個函式就好)
  double get maxTemp => rawPixels.reduce(max);
 
  double get avgTemp => rawPixels.reduce((a, b) => a + b) / rawPixels.length;
 
  double get deltaT => maxTemp - avgTemp;
 
  /// 依李雅淳提供的規則判斷風險等級:
  ///   高風險: ΔT >= 6.0°C 且 RSSI >= -50 dBm
  ///   注意/警告: ΔT >= 4.0°C 或 RSSI >= -65 dBm
  ///   安全: 其餘情況
  RiskLevel get riskLevel {
    if (deltaT >= 6.0 && rssi >= -50) {
      return RiskLevel.highRisk;
    }
    if (deltaT >= 4.0 || rssi >= -65) {
      return RiskLevel.warning;
    }
    return RiskLevel.safe;
  }
 
  /// 核心功能:將 8x8 原始資料,透過雙線性插值放大成 24x24
  /// 回傳一個長度 24*24 = 576 的一維陣列(以 row-major 排列)
  List<double> toInterpolatedGrid({int targetSize = 24}) {
    const int srcSize = 8;
    final double scale = srcSize / targetSize; // 例如 8/24 = 0.333...
 
    final List<double> result = List.filled(targetSize * targetSize, 0);
 
    for (int ty = 0; ty < targetSize; ty++) {
      for (int tx = 0; tx < targetSize; tx++) {
        // 回推目標點在原始 8x8 網格中對應的「浮點座標」
        // 這裡用 (t + 0.5) * scale - 0.5 而不是單純 t * scale,
        // 是為了讓像素中心對齊,插值結果會比較準確、邊緣不會失真
        double srcX = (tx + 0.5) * scale - 0.5;
        double srcY = (ty + 0.5) * scale - 0.5;
 
        // clamp 避免超出邊界(例如負數或超過 7)
        srcX = srcX.clamp(0, srcSize - 1).toDouble();
        srcY = srcY.clamp(0, srcSize - 1).toDouble();
 
        final int x0 = srcX.floor();
        final int y0 = srcY.floor();
        final int x1 = min(x0 + 1, srcSize - 1);
        final int y1 = min(y0 + 1, srcSize - 1);
 
        final double fx = srcX - x0; // x 方向的插值權重 (0~1)
        final double fy = srcY - y0; // y 方向的插值權重 (0~1)
 
        final double v00 = rawPixels[y0 * srcSize + x0];
        final double v10 = rawPixels[y0 * srcSize + x1];
        final double v01 = rawPixels[y1 * srcSize + x0];
        final double v11 = rawPixels[y1 * srcSize + x1];
 
        // 雙線性插值公式:先在 x 方向做兩次線性插值,
        // 再對這兩個結果在 y 方向做一次線性插值
        final double top = v00 * (1 - fx) + v10 * fx;
        final double bottom = v01 * (1 - fx) + v11 * fx;
        final double value = top * (1 - fy) + bottom * fy;
 
        result[ty * targetSize + tx] = value;
      }
    }
 
    return result;
  }
}
 
