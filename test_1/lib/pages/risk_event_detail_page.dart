// ============================================================
// risk_event_detail_page.dart
// ------------------------------------------------------------
// 點擊地圖上的標記或清單項目後,跳轉到這個詳細頁面,
// 顯示單筆風險事件的完整資訊,並提供刪除按鈕。
//
// 【重點筆記 / 學到的東西】
// - 用 Navigator.pop(context, true) 回傳一個「是否有刪除」的
//   布林值給上一頁,這樣上一頁(地圖頁)才知道要不要重新整理列表,
//   不需要用全域變數或額外的狀態管理套件,適合這種簡單的父子頁面溝通。
// ============================================================

import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class RiskEventDetailPage extends StatelessWidget {
  final RiskEvent event;

  const RiskEventDetailPage({super.key, required this.event});

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除這筆紀錄?'),
        content: const Text('刪除後無法復原,確定要刪除這筆風險紀錄嗎?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed == true && event.id != null) {
      await DatabaseHelper.instance.deleteRiskEvent(event.id!);
      if (!context.mounted) return;
      // 回傳 true 給上一頁,通知它需要重新整理清單/地圖
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHighRisk = event.riskLabel == '高風險';

    return Scaffold(
      appBar: AppBar(title: const Text('風險事件詳情')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Chip(
                label: Text(
                  event.riskLabel,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                backgroundColor: isHighRisk ? Colors.red : Colors.orange,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 24),
            _detailRow(Icons.access_time, '時間', event.timestamp.toString()),
            _detailRow(Icons.thermostat, 'ΔT(溫差)',
                '${event.deltaT.toStringAsFixed(1)}°C'),
            _detailRow(Icons.location_on, '座標',
                '${event.latitude.toStringAsFixed(5)}, ${event.longitude.toStringAsFixed(5)}'),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text('刪除這筆紀錄'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const Spacer(),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }
}