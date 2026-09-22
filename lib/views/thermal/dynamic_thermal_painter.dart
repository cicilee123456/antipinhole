import 'package:flutter/material.dart';

class DynamicThermalPainter extends CustomPainter {
  const DynamicThermalPainter({
    required this.grid64x64,
    required this.minTemp,
    required this.maxTemp,
  }) : assert(grid64x64.length == _gridLength, 'grid64x64 必須包含 4096 筆資料');

  static const _gridSize = 64;
  static const _gridLength = _gridSize * _gridSize;

  final List<double> grid64x64;
  final double minTemp;
  final double maxTemp;

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / _gridSize;
    final cellHeight = size.height / _gridSize;
    // 不設定固定顯示範圍，色彩依本次資料的實際最低與最高溫正規化。
    final temperatureRange = maxTemp - minTemp;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var row = 0; row < _gridSize; row++) {
      final top = row * cellHeight;
      final rowOffset = row * _gridSize;

      for (var column = 0; column < _gridSize; column++) {
        final temperature = grid64x64[rowOffset + column];
        final normalized = temperatureRange == 0
            ? 0.0
            : ((temperature - minTemp) / temperatureRange)
                  .clamp(0.0, 1.0)
                  .toDouble();

        paint.color = _colorFor(normalized);

        // 向外擴張 0.5px，避免相鄰矩形因浮點誤差產生白色接縫。
        final left = column * cellWidth - 0.5;
        final topWithTolerance = top - 0.5;
        canvas.drawRect(
          Rect.fromLTWH(
            left,
            topWithTolerance,
            cellWidth + 0.5,
            cellHeight + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant DynamicThermalPainter oldDelegate) {
    return oldDelegate.grid64x64 != grid64x64 ||
        oldDelegate.minTemp != minTemp ||
        oldDelegate.maxTemp != maxTemp;
  }

  static Color _colorFor(double normalized) {
    if (normalized <= 0.2) {
      return Color.lerp(
        const Color(0xFF160B3D),
        const Color(0xFF173BCE),
        normalized / 0.2,
      )!;
    }
    if (normalized <= 0.4) {
      return Color.lerp(
        const Color(0xFF173BCE),
        const Color(0xFF00A8E8),
        (normalized - 0.2) / 0.2,
      )!;
    }
    if (normalized <= 0.6) {
      return Color.lerp(
        const Color(0xFF00A8E8),
        const Color(0xFF35C759),
        (normalized - 0.4) / 0.2,
      )!;
    }
    if (normalized <= 0.75) {
      return Color.lerp(
        const Color(0xFF35C759),
        const Color(0xFFFFD21F),
        (normalized - 0.6) / 0.15,
      )!;
    }
    if (normalized <= 0.9) {
      return Color.lerp(
        const Color(0xFFFFD21F),
        const Color(0xFFFF5A1F),
        (normalized - 0.75) / 0.15,
      )!;
    }
    return Color.lerp(
      const Color(0xFFFF5A1F),
      const Color(0xFF7A0019),
      (normalized - 0.9) / 0.1,
    )!;
  }
}