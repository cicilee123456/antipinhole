import 'package:flutter/material.dart';

import 'views/history/history_view.dart';
import 'views/map/safety_map_screen.dart';
import 'views/settings/settings_view.dart';
import 'views/thermal/thermal_scan_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  static const _pageTitles = ['總覽 Dashboard', '熱成像掃描', '安全地圖', '歷史紀錄', '系統設定'];
  static const _pages = <Widget>[
    _DashboardView(),
    ThermalScanView(),
    SafetyMapScreen(),
    HistoryView(),
    SettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_pageTitles[_selectedIndex])),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: '總覽'),
          NavigationDestination(icon: Icon(Icons.thermostat_outlined), selectedIcon: Icon(Icons.thermostat), label: '熱成像'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: '地圖'),
          NavigationDestination(icon: Icon(Icons.history), label: '歷史'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.all(20),
      crossAxisCount: MediaQuery.sizeOf(context).width >= 600 ? 2 : 1,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.8,
      children: const [
        _DashboardCard(icon: Icons.thermostat, title: '熱成像掃描', description: '查看即時熱點與風險判定', color: Colors.deepOrange),
        _DashboardCard(icon: Icons.history, title: '歷史紀錄', description: '查看過往掃描結果', color: Colors.indigo),
        _DashboardCard(icon: Icons.bluetooth, title: '硬體連線', description: '管理熱感測器連線狀態', color: Colors.teal),
        _DashboardCard(icon: Icons.shield_outlined, title: '安全狀態', description: '系統目前可正常進行 POC 掃描', color: Colors.green),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}