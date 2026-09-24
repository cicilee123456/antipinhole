import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/detection_record.dart';
import '../../services/database_helper.dart';
import '../../services/record_change_notifier.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  late Future<List<DetectionRecord>> _recordsFuture;
  StreamSubscription<DetectionRecord>? _recordSubscription;

  @override
  void initState() {
    super.initState();
    _reload();
    _recordSubscription = RecordChangeNotifier.instance.changes.listen((_) {
      if (mounted) setState(_reload);
    });
  }

  void _reload() {
    _recordsFuture = DatabaseHelper.instance.getAllRecords();
  }

  @override
  void dispose() {
    _recordSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DetectionRecord>>(
      future: _recordsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('無法讀取歷史紀錄：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = snapshot.data!;
        if (records.isEmpty) {
          return const Center(child: Text('目前尚無異常紀錄'));
        }
        return RefreshIndicator(
          onRefresh: () async => setState(_reload),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _RecordTile(record: records[index]),
          ),
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
    final isDanger = record.statusColor == 'RED';
    return Card(
      child: ListTile(
        leading: Icon(
          isDanger ? Icons.warning_rounded : Icons.help_outline,
          color: isDanger ? Colors.red : Colors.amber.shade800,
        ),
        title: Text(isDanger ? '確認高風險事件' : '待驗證疑慮事件'),
        subtitle: Text(
          '${_formatDateTime(record.timestamp)}\n'
          '溫差 ${record.maxDeltaT.toStringAsFixed(1)} °C  ·  '
          'RSSI ${record.maxRSSI.toStringAsFixed(1)} dBm',
        ),
        isThreeLine: true,
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.year}/${twoDigits(local.month)}/${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}
