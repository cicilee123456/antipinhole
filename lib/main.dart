import 'package:flutter/material.dart';

import 'home_page.dart';
import 'services/database_factory.dart';

// App 入口只負責建立根元件，功能頁面由 HomePage 管理。
void main() {
  initializeDatabaseFactory();
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}