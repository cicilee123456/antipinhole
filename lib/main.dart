import 'package:flutter/material.dart';

import 'home_page.dart';
import 'services/database_factory.dart';
import 'services/hardware_connection_service.dart';

// App 入口只負責建立根元件，功能頁面由 HomePage 管理。
void main() {
  initializeDatabaseFactory();
  runApp(const AntiPinholeApp());
}

class AntiPinholeApp extends StatefulWidget {
  const AntiPinholeApp({super.key});

  @override
  State<AntiPinholeApp> createState() => _AntiPinholeAppState();
}

class _AntiPinholeAppState extends State<AntiPinholeApp> {
  final _hardwareService = HardwareConnectionService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anti-Pinhole Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFFAEB8C4)),
        useMaterial3: true,
      ),
      builder: (context, child) => HardwareConnectionScope(
        service: _hardwareService,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomePage(),
    );
  }

  @override
  void dispose() {
    _hardwareService.dispose();
    super.dispose();
  }
}
