import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'dynamic_thermal_painter.dart';

class ThermalHeatmap64View extends StatefulWidget {
  const ThermalHeatmap64View({
    super.key,
    this.temperatures,
    this.minTemp = 20.0,
    this.maxTemp = 40.0,
    this.warningThreshold = 35.0,
  });

  static const int gridSize = 64;
  static const int pixelByteLength = gridSize * gridSize * 4;
  static const List<int> _colorStops = [
    0xFF0000FF,
    0xFF00FFFF,
    0xFF00FF00,
    0xFFFFFF00,
    0xFFFF0000,
  ];

  /// Null input enables a 100 ms mock stream with a pulsing central hotspot.
  final List<List<double>>? temperatures;
  final double minTemp;
  final double maxTemp;
  final double warningThreshold;

  static Uint8List encodePixels(
    List<List<double>> temperatures, {
    double minTemp = 20.0,
    double maxTemp = 40.0,
  }) {
    if (temperatures.length != gridSize ||
        temperatures.any((row) => row.length != gridSize)) {
      throw ArgumentError.value(
        temperatures,
        'temperatures',
        '溫度資料必須是 64x64 二維陣列',
      );
    }
    if (!minTemp.isFinite || !maxTemp.isFinite || maxTemp <= minTemp) {
      throw ArgumentError('maxTemp 必須是大於有限 minTemp 的有限數值');
    }

    final pixels = Uint8List(pixelByteLength);
    var pixelIndex = 0;
    final temperatureRange = maxTemp - minTemp;

    for (final row in temperatures) {
      for (final temperature in row) {
        if (!temperature.isFinite) {
          throw ArgumentError.value(
            temperature,
            'temperatures',
            '溫度值必須是有限數值',
          );
        }
        final normalized = ((temperature - minTemp) / temperatureRange)
            .clamp(0.0, 1.0)
            .toDouble();
        final scaledStop = normalized * (_colorStops.length - 1);
        final lowerStop = math.min(
          scaledStop.floor(),
          _colorStops.length - 2,
        );
        final lowerColor = _colorStops[lowerStop];
        final upperColor = _colorStops[lowerStop + 1];
        final weight = scaledStop - lowerStop;
        pixels[pixelIndex++] = _interpolateChannel(
          (lowerColor >> 16) & 0xFF,
          (upperColor >> 16) & 0xFF,
          weight,
        );
        pixels[pixelIndex++] = _interpolateChannel(
          (lowerColor >> 8) & 0xFF,
          (upperColor >> 8) & 0xFF,
          weight,
        );
        pixels[pixelIndex++] = _interpolateChannel(
          lowerColor & 0xFF,
          upperColor & 0xFF,
          weight,
        );
        pixels[pixelIndex++] = 255;
      }
    }
    return pixels;
  }

  static int _interpolateChannel(int lower, int upper, double weight) {
    return (lower + (upper - lower) * weight).round();
  }

  static List<List<double>> generateMockData({double phase = 0.0}) {
    final heat = 7.0 + 2.0 * math.sin(phase);
    return List<List<double>>.generate(
      gridSize,
      (y) => List<double>.generate(gridSize, (x) {
        final dx = x - (gridSize - 1) / 2;
        final dy = y - (gridSize - 1) / 2;
        final distanceSquared = dx * dx + dy * dy;
        final hotspot = heat * math.exp(-distanceSquared / 7.0);
        final ambient = 24.0 + 0.35 * math.sin((x + y + phase) / 8.0);
        return ambient + hotspot;
      }, growable: false),
      growable: false,
    );
  }

  @override
  State<ThermalHeatmap64View> createState() => _ThermalHeatmap64ViewState();
}

class _ThermalHeatmap64ViewState extends State<ThermalHeatmap64View> {
  List<List<double>>? _temperatures;
  ui.Image? _image;
  Timer? _mockTimer;
  int _imageGeneration = 0;
  double _mockPhase = 0;
  double _minimumTemperature = 0;
  double _maximumTemperature = 0;
  double _averageTemperature = 0;

  @override
  void initState() {
    super.initState();
    _temperatures =
        widget.temperatures ?? ThermalHeatmap64View.generateMockData();
    _updateTemperatureStats(_temperatures!);
    _renderImage(_temperatures!);
    if (widget.temperatures == null) _startMockStream();
  }

  @override
  void didUpdateWidget(covariant ThermalHeatmap64View oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.temperatures == null) {
      if (oldWidget.temperatures != null) {
        _temperatures = ThermalHeatmap64View.generateMockData(
          phase: _mockPhase,
        );
        _updateTemperatureStats(_temperatures!);
        _renderImage(_temperatures!);
        _startMockStream();
      } else if (oldWidget.minTemp != widget.minTemp ||
          oldWidget.maxTemp != widget.maxTemp) {
        _renderImage(_temperatures!);
      }
    } else {
      _mockTimer?.cancel();
      _mockTimer = null;
      if (!identical(oldWidget.temperatures, widget.temperatures) ||
          oldWidget.minTemp != widget.minTemp ||
          oldWidget.maxTemp != widget.maxTemp) {
        _temperatures = widget.temperatures;
        _updateTemperatureStats(_temperatures!);
        _renderImage(_temperatures!);
      }
    }
  }

  void _startMockStream() {
    _mockTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      _mockPhase += 0.22;
      final nextTemperatures = ThermalHeatmap64View.generateMockData(
        phase: _mockPhase,
      );
      _temperatures = nextTemperatures;
      _updateTemperatureStats(nextTemperatures);
      _renderImage(nextTemperatures);
    });
  }

  void _updateTemperatureStats(List<List<double>> temperatures) {
    var minimum = double.infinity;
    var maximum = double.negativeInfinity;
    var total = 0.0;
    for (final row in temperatures) {
      for (final temperature in row) {
        minimum = math.min(minimum, temperature);
        maximum = math.max(maximum, temperature);
        total += temperature;
      }
    }
    _minimumTemperature = minimum;
    _maximumTemperature = maximum;
    _averageTemperature = total /
        (ThermalHeatmap64View.gridSize * ThermalHeatmap64View.gridSize);
  }

  void _renderImage(List<List<double>> temperatures) {
    final generation = ++_imageGeneration;
    final pixels = ThermalHeatmap64View.encodePixels(
      temperatures,
      minTemp: widget.minTemp,
      maxTemp: widget.maxTemp,
    );
    ui.decodeImageFromPixels(
      pixels,
      ThermalHeatmap64View.gridSize,
      ThermalHeatmap64View.gridSize,
      ui.PixelFormat.rgba8888,
      (decodedImage) {
        if (!mounted || generation != _imageGeneration) {
          decodedImage.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = decodedImage;
        });
      },
    );
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    _imageGeneration++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWarning = _maximumTemperature > widget.warningThreshold;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isWarning ? Colors.red : colorScheme.outlineVariant,
          width: isWarning ? 3 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 1,
                child: ColoredBox(
                  color: const Color(0xFF101820),
                  child: CustomPaint(
                    painter: DynamicThermalPainter(image: _image),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 12,
              children: [
                _TemperatureMetric(
                  label: 'Min Temp',
                  value: _minimumTemperature,
                ),
                _TemperatureMetric(
                  label: 'Max Temp',
                  value: _maximumTemperature,
                ),
                _TemperatureMetric(
                  label: 'Avg Temp',
                  value: _averageTemperature,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TemperatureMetric extends StatelessWidget {
  const _TemperatureMetric({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          '${value.toStringAsFixed(1)} °C',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}
