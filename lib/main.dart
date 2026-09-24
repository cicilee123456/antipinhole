import 'package:flutter/material.dart';

import 'home_page.dart';

// App 入口只負責建立根元件，功能頁面由 HomePage 管理。
void main() {
  runApp(const AntiPinholeApp());
}

class AntiPinholeApp extends StatelessWidget {
  const AntiPinholeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 全域主題集中在入口設定，方便後續替換品牌色或 Material 設計。
    return MaterialApp(
      title: 'Anti-Pinhole Detector',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF806044),
          surface: const Color(0xFFF7F2EA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F2EA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F2EA),
          foregroundColor: Color(0xFF332B24),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFFFFFCF8),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFFFFFCF8),
          indicatorColor: const Color(0xFFE6D7C5),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
