import 'package:flutter/material.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        ListTile(
          leading: Icon(Icons.bluetooth),
          title: Text('硬體連線'),
          subtitle: Text('尚未連接熱感測器'),
          trailing: Icon(Icons.chevron_right),
        ),
        Divider(),
        ListTile(
          leading: Icon(Icons.notifications_outlined),
          title: Text('警示設定'),
          subtitle: Text('管理高風險通知與 SOP 顯示'),
          trailing: Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}