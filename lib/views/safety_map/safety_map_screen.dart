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
  late Future<List<DetectionRecord>> _recordsFuture;

  @override
  void initState() {
    super.initState();
    _reloadRecords();
  }

  void _reloadRecords() {
    _recordsFuture = DatabaseHelper.instance.getAllRecords();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DetectionRecord>>(
      future: _recordsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('無法讀取地圖紀錄：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final records = snapshot.data!;
        return Stack(
          children: [
            FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(23.6978, 120.9605),
                initialZoom: 7,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.anti_pinhole',
                ),
                MarkerLayer(
                  markers: records.map(_buildMarker).toList(growable: false),
                ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LegendItem(color: Colors.red, label: '確認高風險'),
                      _LegendItem(color: Colors.amber, label: '待驗證疑慮'),
                    ],
                  ),
                ),
              ),
            ),
            if (records.isEmpty) const _EmptyMapNotice(),
          ],
        );
      },
    );
  }

  Marker _buildMarker(DetectionRecord record) {
    final color = record.statusColor == 'RED' ? Colors.red : Colors.amber;
    return Marker(
      point: LatLng(record.latitude, record.longitude),
      width: 48,
      height: 56,
      child: GestureDetector(
        onTap: () => _showRecordDetails(record),
        child: Icon(Icons.location_on, color: color, size: 44),
      ),
    );
  }

  void _showRecordDetails(DetectionRecord record) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.statusColor == 'RED' ? '確認高風險點' : '待驗證疑慮點',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text('時間：${_formatDateTime(record.timestamp)}'),
              Text('溫差 ΔT：${record.maxDeltaT.toStringAsFixed(1)} °C'),
              Text('RSSI：${record.maxRSSI.toStringAsFixed(1)} dBm'),
              const SizedBox(height: 12),
              Text(
                '防護處置建議',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(record.adviceText),
            ],
          ),
        ),
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

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on, color: color, size: 20),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}

class _EmptyMapNotice extends StatelessWidget {
  const _EmptyMapNotice();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.info_outline, size: 18),
                  SizedBox(width: 8),
                  Text('目前尚無高風險地圖紀錄'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}