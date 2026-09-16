import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/detection_record.dart';
import '../../services/database_helper.dart';

class SafetyMapScreen extends StatefulWidget {
  const SafetyMapScreen({super.key});

  @override
  State<SafetyMapScreen> createState() => _SafetyMapScreenState();
}

class _SafetyMapScreenState extends State<SafetyMapScreen> {
  static const _defaultCenter = LatLng(25.0330, 121.5654);
  late final Future<List<DetectionRecord>> _recordsFuture;

  @override
  void initState() {
    super.initState();
    _recordsFuture = DatabaseHelper.instance.getAllRecords();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DetectionRecord>>(
      future: _recordsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('地圖資料載入失敗：${snapshot.error}'));
        }

        final records = snapshot.data ?? const <DetectionRecord>[];
        if (records.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined, size: 56),
                SizedBox(height: 12),
                Text('暫無歷史紀錄'),
              ],
            ),
          );
        }
        final mappableRecords = records
            .where((record) => record.latitude != null && record.longitude != null)
            .toList(growable: false);
        return Stack(
          children: [
            FlutterMap(
              options: const MapOptions(
                initialCenter: _defaultCenter,
                initialZoom: 13,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.antipinhole.app',
                ),
                MarkerLayer(
                  markers: mappableRecords.map(_markerFor).toList(growable: false),
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '紅色：確認異常 ${records.where((record) => record.isDanger).length}  |  '
                          '黃色：待驗證 ${records.where((record) => !record.isDanger).length}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (records.isNotEmpty && mappableRecords.isEmpty)
              const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('已有本機紀錄，但尚未提供座標，因此沒有可顯示的地標。'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Marker _markerFor(DetectionRecord record) {
    final color = record.isDanger ? Colors.red : Colors.amber.shade700;
    return Marker(
      point: LatLng(record.latitude!, record.longitude!),
      width: 48,
      height: 56,
      child: GestureDetector(
        onTap: () => _showRecord(record),
        child: Icon(Icons.location_on, size: 46, color: color),
      ),
    );
  }

  void _showRecord(DetectionRecord record) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.isDanger ? '紅色高風險：確認異常' : '黃色待驗證：無法確定',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text('時間：${_formatTime(record.timestamp)}'),
              Text('溫差 ΔT：${record.maxDeltaT.toStringAsFixed(1)} °C'),
              Text('RSSI：${record.maxRSSI.toStringAsFixed(1)} dBm'),
              const SizedBox(height: 10),
              Text('防護處置：${record.adviceText}'),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}
