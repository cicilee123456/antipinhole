import 'dart:convert';

class Cc1101DiagnosticSample {
  const Cc1101DiagnosticSample({
    required this.capturedAt,
    required this.rssi,
    required this.lqi,
    required this.crcOk,
    required this.receivedPackets,
    required this.lostPackets,
    required this.per,
    required this.distanceMeters,
    required this.rawJson,
  });

  factory Cc1101DiagnosticSample.fromJson(Map<String, dynamic> json) {
    final cc1101 = json['cc1101'];
    final values = cc1101 is Map<String, dynamic>
        ? <String, dynamic>{...json, ...cc1101}
        : json;

    final receivedPackets = _toInt(
      values['received_packets'] ?? values['cc1101_received_packets'],
    );
    final lostPackets = _toInt(
      values['lost_packets'] ?? values['cc1101_lost_packets'],
    );
    final totalPackets = receivedPackets != null && lostPackets != null
        ? receivedPackets + lostPackets
        : null;
    final reportedPer = _toDouble(values['per'] ?? values['cc1101_per']);
    final per = reportedPer ??
        (totalPackets != null && totalPackets > 0
            ? lostPackets! / totalPackets
            : null);

    return Cc1101DiagnosticSample(
      capturedAt: _parseDate(values['captured_at'] ?? values['timestamp']),
      rssi: _toDouble(
        values['cc1101_rssi'] ?? values['rf_rssi'] ?? values['rssi'] ?? values['rf'],
      ),
      lqi: _toDouble(values['cc1101_lqi'] ?? values['lqi']),
      crcOk: _toBool(values['cc1101_crc_ok'] ?? values['crc_ok']),
      receivedPackets: receivedPackets,
      lostPackets: lostPackets,
      per: per,
      distanceMeters: _toDouble(
        values['distance_m'] ?? values['distance_meters'] ?? values['cc1101_distance_m'],
      ),
      rawJson: Map<String, dynamic>.from(json),
    );
  }

  final DateTime capturedAt;
  final double? rssi;
  final double? lqi;
  final bool? crcOk;
  final int? receivedPackets;
  final int? lostPackets;
  final double? per;
  final double? distanceMeters;
  final Map<String, dynamic> rawJson;

  String toJsonLine() => jsonEncode({
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'rssi': rssi,
        'lqi': lqi,
        'crc_ok': crcOk,
        'received_packets': receivedPackets,
        'lost_packets': lostPackets,
        'per': per,
        'distance_m': distanceMeters,
        'raw': rawJson,
      });

  static DateTime _parseDate(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    return parsed?.toLocal() ?? DateTime.now();
  }

  static double? _toDouble(Object? value) {
    return value is num ? value.toDouble() : double.tryParse('$value');
  }

  static int? _toInt(Object? value) {
    return value is num ? value.toInt() : int.tryParse('$value');
  }

  static bool? _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      if (value.toLowerCase() == 'true' || value == '1') return true;
      if (value.toLowerCase() == 'false' || value == '0') return false;
    }
    return null;
  }
}
