import 'package:flutter/material.dart';

enum SopDecision { confirmedDanger, uncertainWarning, normal }

class SopDialog extends StatelessWidget {
  const SopDialog({
    super.key,
    required this.deltaT,
    required this.rssi,
  });

  final double deltaT;
  final double rssi;

  static Future<SopDecision?> show(
    BuildContext context, {
    required double deltaT,
    required double rssi,
  }) {
    return showDialog<SopDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SopDialog(deltaT: deltaT, rssi: rssi),
    );
  }

  static Future<void> showObstructionAdvice(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('物理遮蔽建議'),
        content: const Text(
          '目前無法確認是否為針孔。請先以膠帶遮蔽可疑位置，或拔除該設備電源，再重新掃描並保留現場紀錄。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('了解並儲存待驗證紀錄'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Expanded(child: Text('初級警示：請完成複檢')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('輔助數據', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('發熱溫差 ΔT：${deltaT.toStringAsFixed(1)} °C'),
            Text('RF 訊號 RSSI：${rssi.toStringAsFixed(1)} dBm'),
            const SizedBox(height: 16),
            const _SopStep(
              number: '1',
              icon: Icons.lightbulb_outline,
              title: '關燈排查',
              description: '關閉現場光源，確認熱點是否仍然存在。',
            ),
            const _SopStep(
              number: '2',
              icon: Icons.flashlight_on,
              title: '反射頻閃排查',
              description: '用手電筒從不同角度掃過可疑孔洞，觀察是否有同軸閃爍反光。',
            ),
            const _SopStep(
              number: '3',
              icon: Icons.photo_camera_outlined,
              title: '保留現場',
              description: '若仍有疑慮，先不要移動設備，依下方決策記錄處置。',
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(SopDecision.normal),
          child: const Text('確定正常\n普通雜物'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(SopDecision.uncertainWarning),
          child: const Text('無法確定\n拿捏不準'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(context).pop(SopDecision.confirmedDanger),
          child: const Text('確認異常\n同軸閃爍反光'),
        ),
      ],
    );
  }
}

class _SopStep extends StatelessWidget {
  const _SopStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
  });

  final String number;
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 13, child: Text(number)),
          const SizedBox(width: 10),
          Icon(icon, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
