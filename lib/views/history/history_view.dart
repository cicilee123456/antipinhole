import 'package:flutter/material.dart';

class HistoryView extends StatelessWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text('歷史紀錄', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('後續可在此查看掃描紀錄與位置資訊。'),
        ],
      ),
    );
  }
}