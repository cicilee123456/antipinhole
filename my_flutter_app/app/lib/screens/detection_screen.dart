import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/detection_data.dart';
import '../widgets/sop_guidance_dialog.dart';

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  final Map<String, String> _scenarios = {
    '安全情境': 'assets/mock_safe.json',
    '針孔高風險 (觸發SOP)': 'assets/mock_pinhole_high_risk.json',
    '環境誤報 (低溫高RF/高溫低RF)': 'assets/mock_environment_false_alarm.json',
  };

  late String _selectedScenario;
  DetectionResult? _currentData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedScenario = _scenarios.keys.first;
    _loadScenarioData(_scenarios[_selectedScenario]!);
  }

  Future<void> _loadScenarioData(String assetPath) async {
    setState(() => _isLoading = true);
    try {
      final String jsonString = await rootBundle.loadString(assetPath);
      final Map<String, dynamic> jsonData = jsonDecode(jsonString);
      final result = DetectionResult.fromJson(jsonData);

      setState(() {
        _currentData = result;
        _isLoading = false;
      });

      if (result.isHighRisk) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showSopDialog(result);
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('載入 JSON 失敗: $e')),
      );
    }
  }

  void _showSopDialog(DetectionResult data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SopGuidanceDialog(
        data: data,
        onReportAndRecord: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('事件已標記，通知資料庫與地圖寫入。'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POC 情境切換與 SOP 驗證'),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '選擇 Mock 情境：',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedScenario,
                  isExpanded: true,
                  items: _scenarios.keys.map((name) {
                    return DropdownMenuItem(
                      value: name,
                      child: Text(name),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedScenario = val);
                      _loadScenarioData(_scenarios[val]!);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_currentData != null) ...[
              _buildStatusCard(_currentData!),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Center(
                    child: Text(
                      '（此區預留給葉孟宣的 8x8 熱圖渲染組件）',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(DetectionResult data) {
    Color statusColor;
    String statusText;

    if (data.isHighRisk) {
      statusColor = Colors.red;
      statusText = '高風險 (High Risk)';
    } else if (data.isWarning) {
      statusColor = Colors.orange;
      statusText = '注意 / 警告 (Warning)';
    } else {
      statusColor = Colors.green;
      statusText = '安全 (Safe)';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('狀態判定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  statusText,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetric('ΔT 溫差', '${data.deltaT}°C'),
                _buildMetric('RSSI 強度', '${data.rssi} dBm'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}