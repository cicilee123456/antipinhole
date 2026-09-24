import 'package:flutter/material.dart';

import 'views/history/history_view.dart';
import 'views/settings/settings_view.dart';
import 'views/thermal/thermal_scan_view.dart';

// 外殼頁面負責全域導覽，不直接處理各子模組的業務邏輯。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  // IndexedStack 保留各頁面的狀態，例如切換分頁後不會重置掃描畫面。
  static const _pageTitles = ['總覽 Dashboard', '熱成像掃描', '歷史紀錄', '系統設定'];
  @override
  Widget build(BuildContext context) {
    // Dashboard 只呈現功能入口；實際功能由各 views 子模組負責。
    return Scaffold(
      appBar: AppBar(title: Text(_pageTitles[_selectedIndex])),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _DashboardView(
            onNavigate: (index) => setState(() => _selectedIndex = index),
          ),
          const ThermalScanView(),
          const HistoryView(),
          const SettingsView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: '總覽'),
          NavigationDestination(
              icon: Icon(Icons.thermostat_outlined),
              selectedIcon: Icon(Icons.thermostat),
              label: '熱成像'),
          NavigationDestination(icon: Icon(Icons.history), label: '歷史'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '設定'),
        ],
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '保持警覺，安心檢測',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF332B24),
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '從一次熱成像掃描開始，確認空間安全。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          Card(
            color: const Color(0xFF806044),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          color: Color(0xFFFFF8EF)),
                      const SizedBox(width: 10),
                      Text(
                        '系統狀態良好',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: const Color(0xFFFFF8EF),
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '熱感測器已準備好\n可以開始新的檢測。',
                    style: TextStyle(
                      color: Color(0xFFFFF8EF),
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => onNavigate(1),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('開始熱成像掃描'),
                      style: FilledButton.styleFrom(
                        foregroundColor: const Color(0xFF806044),
                        backgroundColor: const Color(0xFFFFF8EF),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            '快速入口',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF332B24),
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DashboardCard(
                  icon: Icons.history_rounded,
                  title: '歷史紀錄',
                  description: '查看過往掃描',
                  color: const Color(0xFF9A7253),
                  onTap: () => onNavigate(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DashboardCard(
                  icon: Icons.settings_outlined,
                  title: '系統設定',
                  description: '管理裝置與警示',
                  color: const Color(0xFF68715D),
                  onTap: () => onNavigate(3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            '檢測提醒',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF332B24),
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFE8E0D4),
                    foregroundColor: const Color(0xFF806044),
                    child: const Icon(Icons.lightbulb_outline_rounded),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      '掃描前請確認環境光線穩定，並讓鏡頭對準待檢測區域。',
                      style: TextStyle(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 16),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
