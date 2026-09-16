import 'package:flutter/material.dart';

import 'home_page.dart';

void main() {
  runApp(const AntiPinholeApp());
}

class AntiPinholeApp extends StatelessWidget {
  const AntiPinholeApp({super.key});

  @override
  Widget build(BuildContext context) {
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