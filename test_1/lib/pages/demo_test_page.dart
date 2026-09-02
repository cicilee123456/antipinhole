// ============================================================
// demo_test_page.dart
// ------------------------------------------------------------
// 這一頁不是正式功能頁面,是給葉孟宣自己獨立測試用的:
//   下拉選單切換 3 組 Mock 情境 -> 即時顯示熱圖與風險等級
//   -> 若判定高風險,按下按鈕手動寫入 SQLite 並可跳轉地圖確認
//
// 之後彭同學做好正式的「情境切換 + SOP 彈窗」UI 後,
// 這頁的邏輯可以直接搬過去用,不用重寫。
// ============================================================

import 'package:flutter/material.dart';
import '../models/thermal_frame.dart';
import '../widgets/thermal_heatmap.dart';
import '../services/database_helper.dart';
import '../mock/mock_data.dart';
import 'risk_map_page.dart';

class DemoTestPage extends StatefulWidget {
  const DemoTestPage({super.key});

  @override
  State<DemoTestPage> createState() => _DemoTestPageState();
}

class _DemoTestPageState extends State<DemoTestPage> {
  int _selectedIndex = 0;
  late ThermalFrame _frame;

  @override
  void initState() {
    super.initState();
    _frame = ThermalFrame.fromJson(mockScenarios[_selectedIndex].json);
  }

  void _onScenarioChanged(int? index) {
    if (index == null) return;
    setState(() {
      _selectedIndex = index;
      _frame = ThermalFrame.fromJson(mockScenarios[index].json);
    });
  }

  /// 手動觸發「回報並記錄」,模擬整合驗收流程的第 4 步
  ///
  /// 【重點修正】新增前會先檢查「相近位置 + 相近時間內」是否已經有紀錄,
  /// 避免同一個熱點因為連續偵測或使用者連點按鈕而被重複寫入資料庫。
  Future<void> _reportAndSave() async {
    // 假 GPS 座標(POC 階段先寫死,之後可接手機定位權限取得真實座標)
    final double lat = 22.6273 + (0.001 * (_selectedIndex + 1));
    final double lng = 120.3014 + (0.001 * (_selectedIndex + 1));

    final existing = await DatabaseHelper.instance.findNearbyRecentEvent(
      latitude: lat,
      longitude: lng,
    );

    if (existing != null) {
      // 已有相近紀錄,不重複寫入,只提示使用者
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '此區域在 ${existing.timestamp.hour}:${existing.timestamp.minute.toString().padLeft(2, '0')} 已回報過,不重複記錄'),
        ),
      );
      return;
    }

    final event = RiskEvent(
      timestamp: DateTime.now(),
      deltaT: _frame.deltaT,
      latitude: lat,
      longitude: lng,
      riskLabel: _frame.riskLevel == RiskLevel.highRisk ? '高風險' : '注意',
    );

    await DatabaseHelper.instance.insertRiskEvent(event);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已記錄至本機資料庫')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHighRisk = _frame.riskLevel == RiskLevel.highRisk;

    return Scaffold(
      appBar: AppBar(title: const Text('熱圖 / 資料庫 獨立測試頁')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ---- 情境切換下拉選單(彭同學的正式版會做得更完整,這裡先簡易示範) ----
            DropdownButton<int>(
              value: _selectedIndex,
              isExpanded: true,
              items: List.generate(
                mockScenarios.length,
                (i) => DropdownMenuItem(
                  value: i,
                  child: Text(mockScenarios[i].name),
                ),
              ),
              onChanged: _onScenarioChanged,
            ),
            const SizedBox(height: 12),

            // ---- 熱力圖 ----
            ThermalHeatmap(frame: _frame),

            // ---- 溫度 / 風險資訊列 ----
            ThermalInfoBar(frame: _frame),

            const SizedBox(height: 12),

            // ---- 高風險時顯示「回報並記錄」按鈕,呼應驗收標準第 4 點 ----
            if (isHighRisk)
              ElevatedButton.icon(
                onPressed: _reportAndSave,
                icon: const Icon(Icons.warning_amber),
                label: const Text('回報並記錄'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RiskMapPage()),
                );
              },
              icon: const Icon(Icons.map),
              label: const Text('查看風險地圖'),
            ),
          ],
        ),
      ),
    );
  }
}