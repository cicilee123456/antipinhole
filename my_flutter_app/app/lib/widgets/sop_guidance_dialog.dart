import 'package:flutter/material.dart';
import '../models/detection_data.dart';

class SopGuidanceDialog extends StatelessWidget {
  final DetectionResult data;
  final VoidCallback onReportAndRecord;

  const SopGuidanceDialog({
    super.key,
    required this.data,
    required this.onReportAndRecord,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          SizedBox(width: 8),
          Text(
            '高風險排查 SOP 引導',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '偵測到異常熱源與訊號：\nΔT: ${data.deltaT.toStringAsFixed(1)}°C | RSSI: ${data.rssi.toStringAsFixed(0)} dBm',
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            _buildSopStep(
              step: '1',
              title: '關閉室內照明',
              desc: '將房間所有燈光關閉，營造全黑環境以利光學排查。',
              icon: Icons.lightbulb_outline,
            ),
            const SizedBox(height: 12),
            _buildSopStep(
              step: '2',
              title: '手電筒反光檢查',
              desc: '開啟手機手電筒，貼近眼睛平視照射插座、煙霧探測器或可疑孔隙，觀察是否有針孔鏡頭的紅/綠反光點。',
              icon: Icons.flash_on,
            ),
            const SizedBox(height: 12),
            _buildSopStep(
              step: '3',
              title: '物理遮蔽與存證',
              desc: '若發現可疑孔隙，立即使用膠帶或衣物遮蔽，並拍照存證以備報案需求。',
              icon: Icons.shield_outlined,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍後處理'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onReportAndRecord();
          },
          icon: const Icon(Icons.check, size: 18),
          label: const Text('回報並記錄'),
        ),
      ],
    );
  }

  Widget _buildSopStep({
    required String step,
    required String title,
    required String desc,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: Colors.red.shade100,
          child: Text(
            step,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}