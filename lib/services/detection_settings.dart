import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_data.dart';

class DetectionSettings extends ChangeNotifier {
  DetectionSettings._();

  static final instance = DetectionSettings._();

  static const _environmentModeKey = 'thermal.environment_mode';
  static const _thermalEnabledKey = 'thermal.enabled';

  HeatEnvironmentMode _environmentMode = HeatEnvironmentMode.heatSource;
  bool _thermalEnabled = true;
  bool _isLoaded = false;

  HeatEnvironmentMode get environmentMode => _environmentMode;
  bool get thermalEnabled => _thermalEnabled;
  bool get isLoaded => _isLoaded;

  DetectionProfile get profile => DetectionProfile(
        environmentMode: _environmentMode,
        thermalEnabled: _thermalEnabled,
      );

  Future<void> load() async {
    if (_isLoaded) return;
    final preferences = await SharedPreferences.getInstance();
    _environmentMode = preferences.getString(_environmentModeKey) ==
            HeatEnvironmentMode.noHeatSource.name
        ? HeatEnvironmentMode.noHeatSource
        : HeatEnvironmentMode.heatSource;
    _thermalEnabled = preferences.getBool(_thermalEnabledKey) ?? true;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setEnvironmentMode(HeatEnvironmentMode mode) async {
    if (_environmentMode == mode) return;
    _environmentMode = mode;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_environmentModeKey, mode.name);
  }

  Future<void> setThermalEnabled(bool enabled) async {
    if (_thermalEnabled == enabled) return;
    _thermalEnabled = enabled;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_thermalEnabledKey, enabled);
  }
}
