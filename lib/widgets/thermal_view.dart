import 'package:flutter/material.dart';

class ThermalView extends StatelessWidget {
  static const defaultMinimumTemperature = 20.0;
  static const defaultMaximumTemperature = 35.0;

  const ThermalView({
    super.key,
    required this.thermalGrid,
    this.minTemperature,
    this.maxTemperature,
  });

  final List<double> thermalGrid;
  final double? minTemperature;
  final double? maxTemperature;

  @override
  Widget build(BuildContext context) {
    assert(thermalGrid.length == 64, '熱圖必須包含 64 個溫度值');
    final minimum = minTemperature ?? defaultMinimumTemperature;
    final maximum = maxTemperature ?? defaultMaximumTemperature;
    return AspectRatio(
      aspectRatio: 1,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: 64,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemBuilder: (context, index) {
          final temperature = thermalGrid[index];

          return Semantics(
            label: '第 ${index + 1} 格，${temperature.toStringAsFixed(1)} 度',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _colorForTemperature(temperature, minimum, maximum),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        },
      ),
    );
  }

  static Color _colorForTemperature(
    double temperature,
    double minimum,
    double maximum,
  ) {
    final clamped = temperature.clamp(minimum, maximum).toDouble();
    if (clamped <= 26.0) {
      return Color.lerp(
        Colors.blueGrey.shade800,
        Colors.lightBlue,
        ((clamped - minimum) / (26.0 - minimum)).clamp(0.0, 1.0),
      )!;
    }
    if (clamped <= 28.5) {
      return Color.lerp(
        Colors.lightBlue,
        Colors.orange,
        ((clamped - 26.0) / 2.5).clamp(0.0, 1.0),
      )!;
    }
    return Color.lerp(
      Colors.orange,
      Colors.red,
      ((clamped - 28.5) / (maximum - 28.5)).clamp(0.0, 1.0),
    )!;
  }
}