class Vs1838bSample {
  const Vs1838bSample({
    required this.detected,
    this.code,
    this.protocol,
    this.repeat = false,
  });

  factory Vs1838bSample.fromJson(Map<String, dynamic> json) {
    final nested = json['vs1838b'];
    final values = nested is Map<String, dynamic>
        ? <String, dynamic>{...json, ...nested}
        : json;
    return Vs1838bSample(
      detected: _toBool(
            values['detected'] ??
                values['ir_detected'] ??
                values['ir'] ??
                values['present'],
          ) ??
          false,
      code: values['code']?.toString() ??
          values['ir_code']?.toString() ??
          values['remote_code']?.toString(),
      protocol: values['protocol']?.toString(),
      repeat: _toBool(values['repeat'] ?? values['is_repeat']) ?? false,
    );
  }

  static Vs1838bSample? tryFromJson(Map<String, dynamic> json) {
    final nested = json['vs1838b'];
    final hasData = nested is Map<String, dynamic> ||
        json.containsKey('ir') ||
        json.containsKey('ir_detected') ||
        json.containsKey('ir_code') ||
        json.containsKey('vs1838b');
    return hasData ? Vs1838bSample.fromJson(json) : null;
  }

  final bool detected;
  final String? code;
  final String? protocol;
  final bool repeat;

  static bool? _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }
}
