import 'package:flutter/material.dart';

enum SopDecision {
  confirmedDanger,
  uncertainWarning,
}

// 高風險時的人工排查流程，與熱成像頁面保持獨立以便日後擴充。
class SopDialog extends StatelessWidget {
  const SopDialog({super.key});

  static bool _isShowing = false;
  static DateTime? _lastClosedTime;
  static const _cooldown = Duration(seconds: 20);

  static Future<SopDecision?> show(BuildContext context) async {
    if (_isShowing) return null;
    final lastClosedTime = _lastClosedTime;
    if (lastClosedTime != null &&
        DateTime.now().difference(lastClosedTime) < _cooldown) {
      return null;
    }

    _isShowing = true;
    try {
      return await showDialog<SopDecision>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: SopDialog(),
        ),
      );
    } finally {
      _isShowing = false;
      _lastClosedTime = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Expanded(child: Text('高風險排查 SOP')),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SopStep(
            number: '1',
            icon: Icons.lightbulb_outline,
            title: '關燈排查',
            description: '關閉現場光源，重新確認熱源是否仍然存在。',
          ),
          _SopStep(
            number: '2',
            icon: Icons.flashlight_on,
            title: '手電筒檢查',
            description: '使用手電筒從不同角度檢查可疑孔洞或反光。',
          ),
          _SopStep(
            number: '3',
            icon: Icons.photo_camera_outlined,
            title: '物理遮蔽存證',
            description: '遮蔽可疑位置並拍照記錄，保留現場證據。',
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(SopDecision.confirmedDanger),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('複檢異常'),
        ),
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).pop(SopDecision.uncertainWarning),
          child: const Text('複檢正常（疑似誤判）'),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 14, child: Text(number)),
          const SizedBox(width: 12),
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