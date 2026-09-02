// ============================================================
// thermal_heatmap.dart
// ------------------------------------------------------------
// 負責:
//   把 ThermalFrame 提供的 24x24 插值後資料,用 GridView 畫成
//   藍 -> 橙 -> 紅 的熱力圖(色階代表溫度高低)
//
// 【重點筆記 / 學到的東西】
// - GridView.builder 搭配 SliverGridDelegateWithFixedCrossAxisCount
//   是 Flutter 畫「固定欄數网格」最直接的方式,不需要自己算座標。
// - 顏色插值(Color.lerp)可以做出「漸層色階」的效果,比死板的
//   三段式顏色(藍/橙/紅)更接近真實熱像儀的視覺效果。
// - 這裡刻意把「最高溫的那個格子」加上紅色外框,方便肉眼快速
//   定位系統判定的熱點在畫面中的哪個位置,呼應計畫書「紅框標示
//   異常發熱點」的需求。
// ============================================================
 
import 'package:flutter/material.dart';
import '../models/thermal_frame.dart';
 
class ThermalHeatmap extends StatelessWidget {
  final ThermalFrame frame;
  final int gridSize; // 預設 24x24(對應插值後的解析度)
 
  /// 色階對應的溫度範圍,可依實測環境調整
  /// 低於 minTemp 顯示藍色,高於 maxTemp 顯示紅色,中間依比例漸層
  final double minTemp;
  final double maxTemp;
 
  const ThermalHeatmap({
    super.key,
    required this.frame,
    this.gridSize = 24,
    this.minTemp = 20.0,
    this.maxTemp = 38.0,
  });
 
  /// 將單一溫度值轉換成對應的顏色(藍 -> 橙 -> 紅 三段漸層)
  Color _tempToColor(double temp) {
    // 先把溫度正規化到 0.0 ~ 1.0 之間
    double t = (temp - minTemp) / (maxTemp - minTemp);
    t = t.clamp(0.0, 1.0);
 
    if (t < 0.5) {
      // 前半段:藍色 -> 橙色
      final double localT = t / 0.5;
      return Color.lerp(Colors.blue, Colors.orange, localT)!;
    } else {
      // 後半段:橙色 -> 紅色
      final double localT = (t - 0.5) / 0.5;
      return Color.lerp(Colors.orange, Colors.red, localT)!;
    }
  }
 
  @override
  Widget build(BuildContext context) {
    final List<double> gridData =
        frame.toInterpolatedGrid(targetSize: gridSize);
 
    // 找出插值後畫面中最高溫的索引,用來畫外框標示異常熱點
    int maxIndex = 0;
    double maxVal = gridData[0];
    for (int i = 1; i < gridData.length; i++) {
      if (gridData[i] > maxVal) {
        maxVal = gridData[i];
        maxIndex = i;
      }
    }
 
    return AspectRatio(
      aspectRatio: 1, // 保持正方形畫面
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridSize,
            crossAxisSpacing: 0.5,
            mainAxisSpacing: 0.5,
          ),
          itemCount: gridData.length,
          itemBuilder: (context, index) {
            final bool isHotSpot = index == maxIndex;
            return Container(
              decoration: BoxDecoration(
                color: _tempToColor(gridData[index]),
                border: isHotSpot
                    ? Border.all(color: Colors.white, width: 1.5)
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}
 
/// 搭配熱力圖一起顯示的溫度資訊列(最高溫 / ΔT / 風險等級)
/// 拆成獨立元件,方便之後放進不同頁面重複使用
class ThermalInfoBar extends StatelessWidget {
  final ThermalFrame frame;
 
  const ThermalInfoBar({super.key, required this.frame});
 
  String _riskLabel(RiskLevel level) {
    switch (level) {
      case RiskLevel.highRisk:
        return '高風險';
      case RiskLevel.warning:
        return '注意/警告';
      case RiskLevel.safe:
        return '安全';
    }
  }
 
  Color _riskColor(RiskLevel level) {
    switch (level) {
      case RiskLevel.highRisk:
        return Colors.red;
      case RiskLevel.warning:
        return Colors.orange;
      case RiskLevel.safe:
        return Colors.green;
    }
  }
 
  @override
  Widget build(BuildContext context) {
    final risk = frame.riskLevel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _infoChip('最高溫', '${frame.maxTemp.toStringAsFixed(1)}°C'),
          _infoChip('ΔT', '${frame.deltaT.toStringAsFixed(1)}°C'),
          _infoChip('RSSI', '${frame.rssi.toStringAsFixed(0)} dBm'),
          Chip(
            label: Text(
              _riskLabel(risk),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: _riskColor(risk),
          ),
        ],
      ),
    );
  }
 
  Widget _infoChip(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}