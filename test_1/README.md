# 葉孟宣負責部分:熱圖渲染 + 本機資料庫 + 地圖標記

## 檔案結構
```
lib/
  models/thermal_frame.dart      // 資料模型 + 雙線性插值 + 風險判斷
  widgets/thermal_heatmap.dart   // GridView 熱力圖渲染元件
  services/database_helper.dart // SQLite 本機資料庫操作
  pages/risk_map_page.dart      // 風險地圖頁面(讀取資料庫 + 標記)
  pages/demo_test_page.dart     // 獨立測試頁(下拉切換 3 組 Mock 情境)
  mock/mock_data.dart           // 3 組 Mock JSON(安全/高風險/誤報)
  main.dart                     // 測試用進入點
```

## 需要加入 pubspec.yaml 的套件
在專案的 `pubspec.yaml` 的 `dependencies:` 底下加入:

```yaml
dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.3.0
  path: ^1.9.0
  flutter_map: ^7.0.0
  latlong2: ^0.9.0
```

加完後在專案資料夾執行:
```
flutter pub get
```

## 怎麼測試(整合前,自己先跑得動)
1. 把 `lib/` 底下的檔案複製進你們的 Flutter 專案對應資料夾
2. 加好上面的套件,執行 `flutter pub get`
3. 執行 `flutter run`,預設會打開 `DemoTestPage`
4. 用下拉選單切換「安全情境 / 針孔高風險情境 / 環境誤報情境」,
   確認熱力圖顏色、ΔT、風險等級標籤都會跟著變化
5. 切到「針孔高風險情境」時,應該會出現紅色「回報並記錄」按鈕,
   按下去後點「查看風險地圖」,確認地圖上有新增一個紅點標記

## 之後跟隊友整合時
- **接李雅淳的真實 JSON**:把 `mock_data.dart` 換成李雅淳實際提供的
  JSON 檔案讀取邏輯即可,`ThermalFrame.fromJson()` 的格式已經對齊
- **接彭同學的下拉選單/SOP 彈窗**:`DemoTestPage` 裡的簡易下拉選單、
  「回報並記錄」按鈕邏輯都可以直接搬到彭同學做好的正式 UI 裡,
  核心的 `ThermalFrame`、`ThermalHeatmap`、`DatabaseHelper` 都是
  獨立元件,不用改動內部邏輯

## 風險判斷邏輯(對應李雅淳提供的算式)
- 高風險:ΔT >= 6.0°C 且 RSSI >= -50 dBm
- 注意/警告:ΔT >= 4.0°C 或 RSSI >= -65 dBm
- 安全:其餘情況

ΔT 定義為「畫面最高溫 - 全場平均溫」,寫在 `ThermalFrame.deltaT` 裡,
如果李雅淳的正式演算法有不同定義,只要修改這個 getter 就好,
其他地方(熱圖、風險標籤、資料庫)都不用跟著改。
