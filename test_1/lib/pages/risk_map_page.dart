// ============================================================
// risk_map_page.dart
// ------------------------------------------------------------
// 負責:
//   讀取 SQLite 裡的風險事件紀錄,在地圖上用紅點標記出來
//
// 需要在 pubspec.yaml 加入的套件:
//   flutter_map: ^7.0.0
//   latlong2: ^0.9.0
//
// 【重點筆記 / 學到的東西】
// - 這裡選用 flutter_map(搭配 OpenStreetMap 圖磚)而不是
//   google_maps_flutter,原因是 flutter_map 不需要申請 API Key
//   就能顯示地圖,很適合現在還在 POC(概念驗證)階段快速開發、
//   demo 用;之後如果要正式上架,可以再評估要不要換成
//   Google Maps 或其他有街景/導航功能更完整的方案。
// - 地圖上的標記(Marker)是從資料庫「讀出來再畫上去」,不是
//   即時定位,這符合計畫書「離線回報地圖」的設計精神——資料先
//   落地存到本機,再視覺化呈現,而不是每次都要連網才能用。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/database_helper.dart';
import 'risk_event_detail_page.dart';

class RiskMapPage extends StatefulWidget {
  const RiskMapPage({super.key});

  @override
  State<RiskMapPage> createState() => _RiskMapPageState();
}

class _RiskMapPageState extends State<RiskMapPage> {
  List<RiskEvent> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  /// 從資料庫重新讀取所有風險事件
  /// 設計成獨立函式,方便新增事件後從外部呼叫刷新地圖
  Future<void> _loadEvents() async {
    setState(() => _loading = true);
    final events = await DatabaseHelper.instance.getAllRiskEvents();
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  /// 點擊標記或清單項目時,跳轉到詳情頁。
  /// 詳情頁如果執行了刪除,會用 Navigator.pop(context, true) 回傳 true,
  /// 這裡收到 true 後就重新讀取一次資料庫,讓地圖跟清單同步更新。
  Future<void> _openDetail(RiskEvent event) async {
    final bool? deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RiskEventDetailPage(event: event)),
    );
    if (deleted == true) {
      _loadEvents();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 預設地圖中心:如果有歷史紀錄就用最新一筆的座標置中,
    // 沒有紀錄的話用一個預設座標(這裡先用假座標示意)
    final LatLng center = _events.isNotEmpty
        ? LatLng(_events.first.latitude, _events.first.longitude)
        : const LatLng(22.6273, 120.3014); // 預設:高雄科大附近

    return Scaffold(
      appBar: AppBar(
        title: const Text('匿名風險地圖'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEvents,
            tooltip: '重新整理',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 15,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.pinhole_detector',
                      ),
                      MarkerLayer(
                        markers: _events
                            .map(
                              (e) => Marker(
                                point: LatLng(e.latitude, e.longitude),
                                width: 40,
                                height: 40,
                                // 用 GestureDetector 包住圖示,點擊後跳轉詳情頁
                                child: GestureDetector(
                                  onTap: () => _openDetail(e),
                                  child: Tooltip(
                                    message:
                                        '${e.riskLabel}\nΔT: ${e.deltaT.toStringAsFixed(1)}°C\n點擊查看詳情',
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.red,
                                      size: 36,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                // 底部列出歷史紀錄清單,方便不看地圖也能檢視細節
                SizedBox(
                  height: 140,
                  child: _events.isEmpty
                      ? const Center(child: Text('尚無風險紀錄'))
                      : ListView.builder(
                          itemCount: _events.length,
                          itemBuilder: (context, index) {
                            final e = _events[index];
                            return ListTile(
                              leading: const Icon(Icons.warning,
                                  color: Colors.red),
                              title: Text(
                                  '${e.riskLabel} - ΔT ${e.deltaT.toStringAsFixed(1)}°C'),
                              subtitle: Text(e.timestamp.toString()),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openDetail(e),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}