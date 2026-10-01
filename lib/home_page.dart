import 'package:flutter/material.dart';

import 'views/about/about_view.dart';
import 'views/hardware/hardware_monitor_view.dart';
import 'views/settings/settings_view.dart';
import 'views/thermal/thermal_scan_view.dart';
import 'views/safety_map/safety_map_screen.dart';

// 外殼頁面負責全域導覽，不直接處理各子模組的業務邏輯。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 1;

  // IndexedStack 保留各頁面的狀態，例如切換分頁後不會重置掃描畫面。
  static const _pageTitles = [
    '熱成像掃描',
    '硬體監控',
    '安全地圖',
    '系統設定',
    '關於',
  ];
  late final _pages = <Widget>[
    const ThermalScanView(),
    const HardwareMonitorView(),
    const SafetyMapScreen(),
    const SettingsView(),
    const AboutView(),
  ];

  void _selectPage(int index) {
    setState(() => _selectedIndex = index);
    _scaffoldKey.currentState?.closeDrawer();
  }

  Widget _drawerItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: _selectedIndex == index,
      onTap: () => _selectPage(index),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(title: Text(_pageTitles[_selectedIndex])),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 16, 16),
                child: Text(
                  'Anti-Pinhole Detector',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              _drawerItem(
                  index: 0, icon: Icons.thermostat_outlined, label: '熱成像'),
              _drawerItem(
                  index: 1, icon: Icons.monitor_heart_outlined, label: '硬體監控'),
              _drawerItem(index: 2, icon: Icons.map_outlined, label: '安全地圖'),
              _drawerItem(index: 3, icon: Icons.settings_outlined, label: '設定'),
              _drawerItem(index: 4, icon: Icons.info_outline, label: '關於'),
            ],
          ),
        ),
      ),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: _selectedIndex < 3
    ? SafeArea(
        top: false,
        // 1. 調整左右邊距控制「寬度」（左右各 50 讓它變短變小）
        minimum: const EdgeInsets.fromLTRB(50, 0, 50, 10),
        child: Material(
          color: const Color(0xFFAEB8C4).withValues(alpha: 0.85),
          elevation: 4,
          shadowColor: Colors.black12,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          // 2. 調整「高度」壓扁（改為 54）
          child: SizedBox(
            height: 40,
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                // 縮小選中時的藥丸高亮大小
                indicatorShape: const StadiumBorder(),
                indicatorColor: Colors.white.withValues(alpha: 0.5),
                // 縮小文字字級
                labelTextStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
                // 縮小圖示大小
                iconTheme: WidgetStateProperty.all(
                  const IconThemeData(size: 20),
                ),
              ),
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedIndex: _selectedIndex,
                // 只在選中時顯示文字，或設為 alwaysShow / alwaysHide
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                onDestinationSelected: (index) {
                  setState(() => _selectedIndex = index);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.thermostat_outlined),
                    selectedIcon: Icon(Icons.thermostat),
                    label: '熱成像',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.monitor_heart_outlined),
                    selectedIcon: Icon(Icons.monitor_heart),
                    label: '硬體監控',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon: Icon(Icons.map),
                    label: '安全地圖',
                  ),
                ],
              ),
            ),
          ),
        ),
      )
    : null,