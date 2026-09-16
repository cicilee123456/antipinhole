import 'dart:math';

import '../models/scan_data.dart';

class ThermalSimulator {
  const ThermalSimulator();

  ScanData scan() {
    final random = Random();
    final hotspotX = random.nextInt(8);
    final hotspotY = random.nextInt(8);
    final hotspotStrength = 6.0 + random.nextDouble() * 4.0;
    final thermalGrid = List<double>.generate(64, (index) {
      final x = index % 8;
      final y = index ~/ 8;
      final distance = sqrt(pow(x - hotspotX, 2) + pow(y - hotspotY, 2));
      final hotspot = max(0.0, 1.0 - (distance / 4.0)) * hotspotStrength;
      final ambientNoise = random.nextDouble() * 0.8;
      return 24.0 + ambientNoise + hotspot;
    }, growable: false);

    return ScanData(
      id: 'random-${DateTime.now().microsecondsSinceEpoch}',
      deviceName: 'Random Thermal Sensor',
      rssi: -78.0 + random.nextDouble() * 36.0,
      thermalGrid: thermalGrid,
      capturedAt: DateTime.now().toIso8601String(),
    );
  }
}