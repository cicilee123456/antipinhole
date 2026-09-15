class DetectionResult {
  final double deltaT;
  final double rssi;
  final List<double>? rawHeatmap;

  DetectionResult({
    required this.deltaT,
    required this.rssi,
    this.rawHeatmap,
  });

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      deltaT: (json['delta_t'] as num).toDouble(),
      rssi: (json['rssi'] as num).toDouble(),
      rawHeatmap: json['raw_heatmap'] != null
          ? List<double>.from(json['raw_heatmap'].map((x) => (x as num).toDouble()))
          : null,
    );
  }

  bool get isHighRisk => deltaT >= 6.0 && rssi >= -50.0;
  bool get isWarning => !isHighRisk && (deltaT >= 4.0 || rssi >= -65.0);
}