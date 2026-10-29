import 'package:flutter/material.dart';

import '../thermal/thermal_scan_view.dart';

// 硬體監控使用與熱成像掃描完全相同的即時掃描介面。
class HardwareMonitorView extends StatelessWidget {
  const HardwareMonitorView({super.key});

  @override
  Widget build(BuildContext context) {
    return const ThermalScanView();
  }
}
