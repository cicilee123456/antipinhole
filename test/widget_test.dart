import 'package:anti_pinhole/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts with the integrated hardware monitor',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AntiPinholeApp());

    expect(find.text('硬體監控'), findsNWidgets(2));
    expect(find.text('CC1101_BLE'), findsOneWidget);
    expect(find.text('ESP32 Wi-Fi'), findsNothing);
    expect(find.text('CC1101 藍牙'), findsNothing);
  });
}
