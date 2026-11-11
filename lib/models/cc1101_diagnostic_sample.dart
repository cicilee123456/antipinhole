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
    this.thermalPixels,
    this.irDetected,
    this.irProtocol,
    this.irAddress,
    this.irCommand,
  });

  factory Cc1101DiagnosticSample.fromJson(Map<String, dynamic> json) {
    final cc1101 = json['cc1101'];
    final values = cc1101 is Map<String, dynamic>
        ? <String, dynamic>{...json, ...cc1101}
        : json;
    final amg8833 = values['amg8833'];
    final thermalSource = amg8833 is Map<String, dynamic>
        ? amg8833['pixels'] ?? amg8833['thermal']
        : amg8833 ??
            values['thermal_pixels'] ??
            values['thermal'] ??
            values['pixels'];
    final thermalPixels =
        thermalSource is List ? _parseThermalPixels(thermalSource) : null;
    final vs1838b = values['vs1838b'];
    final irValues = vs1838b is Map<String, dynamic>
        ? <String, dynamic>{...values, ...vs1838b}
        : values;

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
        values['cc1101_rssi'] ??
            values['CC1101RSSI'] ??
            values['CC1101_RSSI'] ??
            values['cc1101RSSI'] ??
            values['rf_cc1101_rssi'] ??
            values['rssi'] ??
            values['rf_rssi'] ??
            values['rf'],
      ),
      lqi: _toDouble(
        values['cc1101_lqi'] ?? values['CC1101LQI'] ?? values['lqi'],
      ),
      crcOk: _toBool(
        values['cc1101_crc_ok'] ?? values['CC1101CRCOK'] ?? values['crc_ok'],
      ),
      receivedPackets: receivedPackets,
      lostPackets: lostPackets,
      per: per,
      distanceMeters: _toDouble(
        values['distance_m'] ??
            values['distance_meters'] ??
            values['cc1101_distance_m'],
      ),
      rawJson: Map<String, dynamic>.from(json),
      thermalPixels: thermalPixels,
      irDetected: _toBool(
        irValues['ir_detected'] ?? irValues['detected'] ?? irValues['ir'],
      ),
      irProtocol:
          _toStringOrNull(irValues['ir_protocol'] ?? irValues['protocol']),
      irAddress: _toStringOrNull(irValues['ir_address'] ?? irValues['address']),
      irCommand: _toStringOrNull(irValues['ir_command'] ?? irValues['command']),
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
  final List<double>? thermalPixels;
  final bool? irDetected;
  final String? irProtocol;
  final String? irAddress;
  final String? irCommand;

  String toJsonLine() => jsonEncode({
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'rssi': rssi,
        'lqi': lqi,
        'crc_ok': crcOk,
        'received_packets': receivedPackets,
        'lost_packets': lostPackets,
        'per': per,
        'distance_m': distanceMeters,
        'thermal_pixels': thermalPixels,
        'ir_detected': irDetected,
        'ir_protocol': irProtocol,
        'ir_address': irAddress,
        'ir_command': irCommand,
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

  static List<double> _parseThermalPixels(List<dynamic> values) {
    if (values.length != 64) {
      throw const FormatException('AMG8833 thermal pixels 必須是長度 64 的陣列');
    }
    return values.map((value) {
      if (value is num) return value.toDouble();
      throw const FormatException('AMG8833 thermal pixels 只能包含數值');
    }).toList(growable: false);
  }

  static String? _toStringOrNull(Object? value) => value?.toString();
}
