import 'package:anti_pinhole/views/thermal/thermal_heatmap64_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThermalHeatmap64View.encodePixels', () {
    test('encodes 64x64 temperatures as clamped RGBA pixels', () {
      final temperatures = List<List<double>>.generate(
        64,
        (row) => List<double>.generate(
          64,
          (column) {
            if (row == 0 && column == 0) return -10;
            if (row == 0 && column == 1) return 30;
            if (row == 0 && column == 2) return 50;
            return 25;
          },
          growable: false,
        ),
        growable: false,
      );

      final pixels = ThermalHeatmap64View.encodePixels(temperatures);

      expect(pixels, hasLength(64 * 64 * 4));
      expect(pixels.sublist(0, 4), [0, 0, 255, 255]);
      expect(pixels.sublist(4, 8), [0, 255, 0, 255]);
      expect(pixels.sublist(8, 12), [255, 0, 0, 255]);
    });

    test('rejects invalid dimensions and temperature ranges', () {
      expect(
        () => ThermalHeatmap64View.encodePixels(const []),
        throwsArgumentError,
      );
      expect(
        () => ThermalHeatmap64View.encodePixels(
          List<List<double>>.generate(64, (_) => List.filled(64, 25.0)),
          minTemp: 40,
          maxTemp: 20,
        ),
        throwsArgumentError,
      );
    });
  });

  testWidgets('shows min, max, and average temperatures', (tester) async {
    final temperatures = List<List<double>>.generate(
      64,
      (row) => List<double>.filled(64, row.toDouble()),
      growable: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: ThermalHeatmap64View(
                temperatures: temperatures,
                minTemp: 0,
                maxTemp: 63,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('最低溫度'), findsOneWidget);
    expect(find.text('最高溫度'), findsOneWidget);
    expect(find.text('平均溫度'), findsOneWidget);
    expect(find.text('0.0 °C'), findsOneWidget);
    expect(find.text('63.0 °C'), findsOneWidget);
    expect(find.text('31.5 °C'), findsOneWidget);
  });
}
