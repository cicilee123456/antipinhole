import 'package:flutter/material.dart';

class SOPGuideDialog extends StatelessWidget {
  const SOPGuideDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SOPGuideDialog(),
    );
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('我已了解'),
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