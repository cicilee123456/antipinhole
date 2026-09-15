import 'dart:math' as math;

enum DetectionLevel {
  safe(0, '安全'),
  warning(1, '警示'),
  highRisk(2, '高風險');

  const DetectionLevel(this.value, this.label);

  final int value;
  final String label;
}

class DetectionScenario {
  const DetectionScenario({
    required this.id,
    required this.deviceName,
    required this.rssi,
    required this.thermalGrid,
    this.capturedAt,
  });

  factory DetectionScenario.fromJson(Map<String, dynamic> json) {
    final rawGrid = json['thermal_grid'];
    if (rawGrid is! List || rawGrid.length != 64) {
      throw const FormatException('thermal_grid 必須是長度 64 的陣列');
    }

    final grid = rawGrid.map((value) {
      if (value is num) return value.toDouble();
      throw const FormatException('thermal_grid 只能包含數值');
    }).toList(growable: false);

    final rssi = json['rssi'];
    if (rssi is! num) {
      throw const FormatException('rssi 必須是數值');
    }

    return DetectionScenario(
      id: json['id']?.toString() ?? 'unknown',
      deviceName: json['device_name']?.toString() ?? '未命名裝置',
      rssi: rssi.toDouble(),
      thermalGrid: grid,
      capturedAt: json['captured_at']?.toString(),
    );
  }

  final String id;
  final String deviceName;
  final double rssi;
  final List<double> thermalGrid;
  final String? capturedAt;

  DetectionResult analyze() => DetectionAnalyzer.evaluate(this);
}

class DetectionResult {
  const DetectionResult({
    required this.level,
    required this.deltaT,
    required this.minimumTemperature,
    required this.maximumTemperature,
    required this.rssi,
    required this.weightedScore,
  });

  final DetectionLevel level;
  final double deltaT;
  final double minimumTemperature;
  final double maximumTemperature;
  final double rssi;
  final double weightedScore;

  bool get isHighRisk => level == DetectionLevel.highRisk;
}

class DetectionAnalyzer {
  const DetectionAnalyzer._();

  static DetectionResult evaluate(DetectionScenario scenario) {
    final minimumTemperature = scenario.thermalGrid.reduce(math.min);
    final maximumTemperature = scenario.thermalGrid.reduce(math.max);
    final deltaT = maximumTemperature - minimumTemperature;

    final hasHighThermalDelta = deltaT >= 6.0;
    final hasStrongSignal = scenario.rssi >= -50.0;
    final hasWarningThermalDelta = deltaT >= 4.0;
    final hasWarningSignal = scenario.rssi >= -65.0;

    final level = hasHighThermalDelta && hasStrongSignal
        ? DetectionLevel.highRisk
        : (hasWarningThermalDelta || hasWarningSignal
              ? DetectionLevel.warning
              : DetectionLevel.safe);

    // The score keeps both signals visible to consumers while the level above
    // remains governed by the explicit product thresholds.
    final thermalScore = ((deltaT / 6.0) * 0.6).clamp(0.0, 0.6);
    final signalScore = (((scenario.rssi + 100.0) / 50.0) * 0.4)
        .clamp(0.0, 0.4);

    return DetectionResult(
      level: level,
      deltaT: deltaT,
      minimumTemperature: minimumTemperature,
      maximumTemperature: maximumTemperature,
      rssi: scenario.rssi,
      weightedScore: thermalScore + signalScore,
    );
  }
}