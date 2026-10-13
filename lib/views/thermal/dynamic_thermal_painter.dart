import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class DynamicThermalPainter extends CustomPainter {
  const DynamicThermalPainter({required this.image});

  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final currentImage = image;
    if (currentImage == null) return;

    canvas.drawImageRect(
      currentImage,
      Rect.fromLTWH(
        0,
        0,
        currentImage.width.toDouble(),
        currentImage.height.toDouble(),
      ),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant DynamicThermalPainter oldDelegate) {
    return oldDelegate.image != image;
  }
}
