import 'package:flutter/material.dart';

import '../../models/detection_record.dart';
import '../../services/database_helper.dart';

class HistoryView extends StatelessWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DetectionRecord>>(
      future: DatabaseHelper.instance.getAllRecords(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('紀錄載入失敗：${snapshot.error}'));
        }

        final records = snapshot.data ?? const <DetectionRecord>[];
        if (records.isEmpty) {
          return const Center(child: Text('尚無複檢紀錄'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: records.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _RecordTile(record: records[index]),
        );
      },
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final DetectionRecord record;

  @override
  Widget build(BuildContext context) {
    final color = record.isDanger ? Colors.red : Colors.amber.shade800;
    final label = record.isDanger ? '確認異常' : '待驗證';
    return Card(
      child: ListTile(
        leading: Icon(Icons.location_on, color: color),
        title: Text('$label  |  ΔT ${record.maxDeltaT.toStringAsFixed(1)} °C'),
        subtitle: Text(
          '${record.timestamp.toLocal()}\nRSSI ${record.maxRSSI.toStringAsFixed(1)} dBm\n${record.adviceText}',
        ),
        isThreeLine: true,
      ),
    );
  }
}
