// ============================================================
// main.dart
// ------------------------------------------------------------
// 這是「葉孟宣負責部分」的獨立測試入口,方便你在整合前
// 單獨執行 `flutter run` 就能看到熱圖 + 資料庫 + 地圖的效果。
// 之後跟彭同學、李雅淳的部分整合時,把 DemoTestPage 換成
// 正式的主頁面即可,其他 widget/service 都可以直接沿用。
// ============================================================
 
import 'package:flutter/material.dart';
import 'pages/demo_test_page.dart';
 
void main() {
  runApp(const MyApp());
}
 
class MyApp extends StatelessWidget {
  const MyApp({super.key});
 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '反針孔熱圖測試',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const DemoTestPage(),
    );
  }
}