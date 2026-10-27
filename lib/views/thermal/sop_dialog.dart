import 'package:flutter/material.dart';

enum SopDecision {
  confirmedDanger,
  uncertainWarning,
}

class SopCard extends StatelessWidget {
  const SopCard({
    required this.deltaT,
    required this.rssi,
    this.description,
    required this.snapshotFrozen,
    required this.freezeRemainingSeconds,
    required this.minimized,
    required this.onToggleMinimized,
    required this.onDecision,
    super.key,
  });

  final double? deltaT;
  final double rssi;
  final String? description;
  final bool snapshotFrozen;
  final int freezeRemainingSeconds;
  final bool minimized;
  final VoidCallback onToggleMinimized;
  final Future<void> Function(SopDecision decision) onDecision;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 8,
      color: colorScheme.surfaceContainerHighest,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: minimized
            ? InkWell(
                onTap: onToggleMinimized,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('高風險 SOP 進行中，點擊展開複檢'),
                      ),
                      IconButton(
                        onPressed: onToggleMinimized,
                        icon: const Icon(Icons.keyboard_arrow_up),
                        tooltip: '展開 SOP',
                      ),
                    ],
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '高風險排查 SOP',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: onToggleMinimized,
                          icon: const Icon(Icons.keyboard_arrow_down),
                          tooltip: '收合 SOP',
                        ),
                      ],
                    ),
                    Text(
                      description ??
                          (snapshotFrozen
                              ? '目前顯示異常觸發快照，請確認熱力圖中的異常位置。'
                              : '即時偵測已恢復，請完成現場光學複檢。'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    if (snapshotFrozen)
                      Text(
                        '畫面暫停更新，約 $freezeRemainingSeconds 秒後恢復偵測。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    if (snapshotFrozen) const SizedBox(height: 8),
                    Wrap(
                      spacing: 20,
                      runSpacing: 4,
                      children: [
                        if (deltaT != null)
                          Text(
                            '觸發時 ΔT：${deltaT!.toStringAsFixed(1)} °C',
                          ),
                        Text('觸發時 RSSI：${rssi.toStringAsFixed(1)} dBm'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const _SopStep(
                      number: '1',
                      icon: Icons.lightbulb_outline,
                      title: '關燈排查',
                      description: '關閉現場光源，重新確認熱源是否仍然存在。',
                    ),
                    const _SopStep(
                      number: '2',
                      icon: Icons.flashlight_on,
                      title: '手電筒檢查',
                      description: '使用手電筒從不同角度檢查可疑孔洞或反光。',
                    ),
                    const _SopStep(
                      number: '3',
                      icon: Icons.photo_camera_outlined,
                      title: '物理遮蔽存證',
                      description: '遮蔽可疑位置並拍照記錄，保留現場證據。',
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => onDecision(
                            SopDecision.uncertainWarning,
                          ),
                          child: const Text('複檢正常（疑似誤判）'),
                        ),
                        FilledButton(
                          onPressed: () => onDecision(
                            SopDecision.confirmedDanger,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('複檢異常'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
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
          onPressed: () =>
              Navigator.of(context).pop(SopDecision.confirmedDanger),
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
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
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
