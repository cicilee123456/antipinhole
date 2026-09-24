class DetectionRecord {
  const DetectionRecord({
    this.id,
    required this.timestamp,
    required this.maxDeltaT,
    required this.maxRSSI,
    required this.latitude,
    required this.longitude,
    required this.statusColor,
    required this.userDecision,
    required this.adviceText,
  })  : assert(statusColor == 'RED' || statusColor == 'YELLOW'),
        assert(
          userDecision == 'CONFIRMED_DANGER' ||
              userDecision == 'UNCERTAIN_WARNING',
        );

  factory DetectionRecord.fromMap(Map<String, Object?> map) {
    final statusColor = map['statusColor'] as String;
    final userDecision = map['userDecision'] as String;
    _validateStatus(statusColor, userDecision);

    return DetectionRecord(
      id: (map['id'] as num?)?.toInt(),
      timestamp: DateTime.parse(map['timestamp'] as String),
      maxDeltaT: (map['maxDeltaT'] as num).toDouble(),
      maxRSSI: (map['maxRSSI'] as num).toDouble(),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      statusColor: statusColor,
      userDecision: userDecision,
      adviceText: map['adviceText'] as String,
    );
  }

  final int? id;
  final DateTime timestamp;
  final double maxDeltaT;
  final double maxRSSI;
  final double latitude;
  final double longitude;
  final String statusColor;
  final String userDecision;
  final String adviceText;

  Map<String, Object?> toMap() {
    _validateStatus(statusColor, userDecision);
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.toIso8601String(),
      'maxDeltaT': maxDeltaT,
      'maxRSSI': maxRSSI,
      'latitude': latitude,
      'longitude': longitude,
      'statusColor': statusColor,
      'userDecision': userDecision,
      'adviceText': adviceText,
    };
  }

  static void _validateStatus(String statusColor, String userDecision) {
    if (statusColor != 'RED' && statusColor != 'YELLOW') {
      throw ArgumentError.value(statusColor, 'statusColor', '必須是 RED 或 YELLOW');
    }
    if (userDecision != 'CONFIRMED_DANGER' &&
        userDecision != 'UNCERTAIN_WARNING') {
      throw ArgumentError.value(
        userDecision,
        'userDecision',
        '必須是 CONFIRMED_DANGER 或 UNCERTAIN_WARNING',
      );
    }
  }
}