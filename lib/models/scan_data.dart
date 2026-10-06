import 'dart:typed_data';

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
    this.irDetected = false,
    this.wifiDeviceCount = 0,
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

  factory ScanData.fromHardwareJson(
    Map<String, dynamic> json, {
    required String deviceId,
    required String deviceName,
  }) {
    final rawThermal = json['thermal'];
    if (rawThermal is! List || rawThermal.length != 64) {
      throw const FormatException('硬體 thermal 必須是長度 64 的陣列');
    }

    final thermalGrid = rawThermal.map((value) {
      if (value is num) return value.toDouble();
      throw const FormatException('硬體 thermal 只能包含數值');
    }).toList(growable: false);

    final rawRssi = json['rf'];
    if (rawRssi is! num) {
      throw const FormatException('硬體 rf 必須是數值');
    }

    return ScanData(
      id: '$deviceId-${DateTime.now().microsecondsSinceEpoch}',
      deviceName: deviceName,
      rssi: rawRssi.toDouble(),
      thermalGrid: thermalGrid,
      capturedAt: DateTime.now().toIso8601String(),
      irDetected: json['ir'] == 1 || json['ir'] == true,
      wifiDeviceCount: (json['wifi'] as num?)?.toInt() ?? 0,
    );
  }

  factory ScanData.fromHardwareBinary(
    List<int> payload, {
    required String deviceId,
    required String deviceName,
  }) {
    if (payload.length != 132) {
      throw FormatException(
        'BLE SensorPayload 長度必須是 132 bytes，實際為 ${payload.length}',
      );
    }

    final bytes = Uint8List.fromList(payload);
    final data = ByteData.sublistView(bytes);
    final thermalGrid = List<double>.generate(
      64,
      (index) => data.getInt16(index * 2, Endian.little) / 10.0,
      growable: false,
    );

    return ScanData(
      id: '$deviceId-${DateTime.now().microsecondsSinceEpoch}',
      deviceName: deviceName,
      rssi: data.getInt16(128, Endian.little).toDouble(),
      thermalGrid: thermalGrid,
      capturedAt: DateTime.now().toIso8601String(),
      irDetected: bytes[130] != 0,
      wifiDeviceCount: bytes[131],
    );
  }

  factory ScanData.fromEsp32Json(Map<String, dynamic> json) {
    final rawPixels = json['pixels'];
    if (rawPixels is! List || rawPixels.length != 64) {
      throw const FormatException('ESP32 pixels 必須是長度 64 的陣列');
    }

    final thermalGrid = rawPixels.map((value) {
      if (value is num) return value.toDouble();
      throw const FormatException('ESP32 pixels 只能包含數值');
    }).toList(growable: false);

    return ScanData(
      id: 'esp32-${DateTime.now().microsecondsSinceEpoch}',
      deviceName: json['device_name']?.toString() ?? 'ESP32 Thermal Sensor',
      rssi: ((json['rf_rssi'] ?? json['rssi']) as num?)?.toDouble() ?? -70.0,
      thermalGrid: thermalGrid,
      capturedAt:
          json['captured_at']?.toString() ?? DateTime.now().toIso8601String(),
      irDetected: json['ir'] == 1 || json['ir'] == true,
      wifiDeviceCount: (json['wifi_devices'] as num?)?.toInt() ??
          (json['wifi'] as num?)?.toInt() ??
          0,
    );
  }

  final String id;
  final String deviceName;
  final double rssi;
  final List<double> thermalGrid;
  final String? capturedAt;
  final bool irDetected;
  final int wifiDeviceCount;

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

    // 暫時測試規則：只要 RSSI 高於 -89 dBm 就觸發高風險告警。
    final level =
        scan.rssi > -89.0 ? DetectionLevel.highRisk : DetectionLevel.safe;
    final weightedScore = ((scan.rssi + 89.0) / 89.0).clamp(0.0, 1.0);

    return ScanResult(
      level: level,
      deltaT: deltaT,
      minimumTemperature: minimumTemperature,
      maximumTemperature: maximumTemperature,
      rssi: scan.rssi,
      weightedScore: weightedScore,
    );
  }
}
