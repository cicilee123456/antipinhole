import 'package:flutter/material.dart';

import 'models/detection_model.dart';
import 'services/mock_data_service.dart';
import 'widgets/sop_dialog.dart';
import 'widgets/thermal_view.dart';

void main() {
  runApp(const AntiPinholeApp());
}

class AntiPinholeApp extends StatelessWidget {
  const AntiPinholeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anti-Pinhole Detector',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DetectionPage(),
    );
  }
}

class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  static const _service = MockDataService();
  String _selectedScenario = 'safe';
  DetectionScenario? _scenario;
  Object? _error;
  bool _isLoading = true;
  String? _dialogShownForScenario;

  @override
  void initState() {
    super.initState();
    _loadScenario(_selectedScenario);
  }

  Future<void> _loadScenario(String scenarioKey) async {
    setState(() {
      _selectedScenario = scenarioKey;
      _isLoading = true;
      _error = null;
    });

    try {
      final scenario = await _service.loadScenario(scenarioKey);
      if (!mounted) return;
      setState(() {
        _scenario = scenario;
        _isLoading = false;
      });
      _showRiskDialogAfterBuild(scenario);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  void _showRiskDialogAfterBuild(DetectionScenario scenario) {
    if (!scenario.analyze().isHighRisk || _dialogShownForScenario == scenario.id) {
      return;
    }
    _dialogShownForScenario = scenario.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) SOPGuideDialog.show(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scenario = _scenario;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anti-Pinhole 偵測'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedScenario,
                onChanged: _isLoading
                    ? null
                    : (value) {
                        if (value != null) _loadScenario(value);
                      },
                items: const [
                  DropdownMenuItem(value: 'safe', child: Text('安全常態')),
                  DropdownMenuItem(value: 'danger', child: Text('針孔高風險')),
                  DropdownMenuItem(value: 'warning', child: Text('高溫干擾')),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(scenario),
    );
  }

  Widget _buildBody(DetectionScenario? scenario) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _loadScenario(_selectedScenario),
          icon: const Icon(Icons.refresh),
          label: Text('載入失敗：$_error'),
        ),
      );
    }
    if (scenario == null) return const SizedBox.shrink();

    final result = scenario.analyze();
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = _buildContent(scenario, result);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: constraints.maxWidth >= 720
              ? Center(child: SizedBox(width: 680, child: content))
              : content,
        );
      },
    );
  }

  Widget _buildContent(DetectionScenario scenario, DetectionResult result) {
    final levelColor = switch (result.level) {
      DetectionLevel.safe => Colors.green,
      DetectionLevel.warning => Colors.orange,
      DetectionLevel.highRisk => Colors.red,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('目前判定', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  result.level.label,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: levelColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(scenario.deviceName),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ThermalView(
              thermalGrid: scenario.thermalGrid,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 16,
              spacing: 32,
              children: [
                _Metric(label: '溫差 ΔT', value: '${result.deltaT.toStringAsFixed(1)} °C'),
                _Metric(label: 'RSSI', value: '${result.rssi.toStringAsFixed(1)} dBm'),
                _Metric(label: '裝置名稱', value: scenario.deviceName),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}