class DetectionRecord {
  const DetectionRecord({
    this.id,
    required this.timestamp,
    required this.maxDeltaT,
    required this.maxRSSI,
    this.latitude,
    this.longitude,
    required this.statusColor,
    required this.userDecision,
    required this.adviceText,
  });

  factory DetectionRecord.fromMap(Map<String, Object?> map) {
    return DetectionRecord(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      maxDeltaT: (map['maxDeltaT'] as num).toDouble(),
      maxRSSI: (map['maxRSSI'] as num).toDouble(),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      statusColor: map['statusColor'] as String,
      userDecision: map['userDecision'] as String,
      adviceText: map['adviceText'] as String,
    );
  }

  final int? id;
  final DateTime timestamp;
  final double maxDeltaT;
  final double maxRSSI;
  final double? latitude;
  final double? longitude;
  final String statusColor;
  final String userDecision;
  final String adviceText;

  Map<String, Object?> toMap() => {
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

  bool get isDanger => statusColor == 'RED';
}