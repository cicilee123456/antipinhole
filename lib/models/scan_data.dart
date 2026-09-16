import 'dart:math' as math;

// 風險等級的數值與顯示文字集中管理，避免 UI 各自定義門檻名稱。
enum DetectionLevel {
  safe(0, '安全'),
  warning(1, '警示'),
  highRisk(2, '高風險');

  const DetectionLevel(this.value, this.label);

  final int value;
  final String label;
}

class ScanData {
  const ScanData({
    required this.id,
    required this.deviceName,
    required this.rssi,
    required this.thermalGrid,
    this.capturedAt,
  }) : assert(thermalGrid.length == 64, 'thermalGrid 必須包含 64 筆資料');

  factory ScanData.fromJson(Map<String, dynamic> json) {
    // 外部資料進入系統時先驗證 8x8 熱圖與 RSSI，避免分析階段才出錯。
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

    return ScanData(
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

  ScanResult analyze() => DetectionAnalyzer.evaluate(this);
}

class ScanResult {
  const ScanResult({
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

  static ScanResult evaluate(ScanData scan) {
    final minimumTemperature = scan.thermalGrid.reduce(math.min);
    final maximumTemperature = scan.thermalGrid.reduce(math.max);
    final deltaT = maximumTemperature - minimumTemperature;

    // 高風險必須同時滿足溫差與訊號門檻；警示則任一條件成立即可。
    final highThermalDelta = deltaT >= 6.0;
    final strongSignal = scan.rssi >= -50.0;
    final warningThermalDelta = deltaT >= 4.0;
    final warningSignal = scan.rssi >= -65.0;

    final level = highThermalDelta && strongSignal
        ? DetectionLevel.highRisk
        : warningThermalDelta || warningSignal
            ? DetectionLevel.warning
            : DetectionLevel.safe;

    // 加權分數供後續排序或報表使用，不取代上方明確的等級判定。
    final thermalScore = ((deltaT / 6.0) * 0.6).clamp(0.0, 0.6);
    final signalScore = (((scan.rssi + 100.0) / 50.0) * 0.4)
        .clamp(0.0, 0.4);

    return ScanResult(
      level: level,
      deltaT: deltaT,
      minimumTemperature: minimumTemperature,
      maximumTemperature: maximumTemperature,
      rssi: scan.rssi,
      weightedScore: thermalScore + signalScore,
    );
  }
}