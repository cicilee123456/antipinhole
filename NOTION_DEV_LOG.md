# AntiPinhole Detector｜今日開發日誌

> 日期：2026-09-23  
> 專案：AntiPinhole Detector 反針孔與熱成像偵測 App  
> 平台：Flutter Web / Android / iOS  
> 今日主題：ESP32 BLE 串接、Safety Map、SQLite 與 Web 啟動修復

---

# 今日工作摘要

今天主要將 ESP32 ThermoCam 硬體程式與 Flutter App 進行介接，並處理 Web 版本無法啟動的問題。

完成的核心流程：

```text
ESP32 ThermoCam_BLE
        ↓ BLE JSON
Flutter BLE Service
        ↓
ScanData 熱成像資料模型
        ↓
風險分析與熱圖畫面
        ↓
DetectionRecord / Safety Map
```

---

# 一、ESP32 BLE 硬體資料介接

## 硬體端資料格式

ESP32 透過 BLE Characteristic 推送 JSON，內容包含：

```json
{
  "thermal": [25.0, 25.1, 25.2],
  "rf": -42,
  "ir": 1,
  "wifi": 3
}
```

實際 `thermal` 陣列應包含 64 筆 AMG8833 熱像素資料。

## Flutter 端串接內容

新增 `ThermoCamBleService`，負責：

- 搜尋裝置名稱 `ThermoCam_BLE`
- 連接 BLE Service
- 取得指定 Characteristic
- 開啟 Notification
- 將 JSON 解碼為 `ScanData`
- 將 `thermal` 對應為 64 格熱成像資料
- 將 `rf` 對應為 RSSI
- 保留 `ir` 與 `wifi` 資訊

使用的 UUID：

```text
Service UUID:
4fafc201-1fb5-459e-8fcc-c5c9c331914b

Characteristic UUID:
beb5483e-36e1-4688-b7f5-ea07361b26a8
```

## BLE 使用方式調整

Web Bluetooth 必須由使用者操作觸發，不能在頁面初始化時自動掃描。因此改為：

1. App 進入熱成像頁時先使用模擬資料。
2. 使用者點擊「連接 ThermoCam 硬體」。
3. 瀏覽器開啟 BLE 裝置選擇視窗。
4. 選擇 `ThermoCam_BLE` 後開始接收資料。
5. 若連線失敗，繼續使用模擬資料。

---

# 二、總覽頁硬體配對入口

總覽頁原本只有硬體連線卡片，沒有實際操作功能。

今日已將它接到同一個 BLE 配對流程：

```text
總覽頁「硬體連線」卡片
        ↓
切換至熱成像頁
        ↓
觸發 BLE 裝置配對
        ↓
連線 ThermoCam_BLE
```

這樣總覽頁與熱成像頁共用同一個 `ThermoCamBleService`，避免兩個頁面各自維護不同的連線狀態。

---

# 三、DetectionRecord 資料模型

新增 `DetectionRecord`，用於保存地圖與歷史紀錄資料。

欄位包含：

| 欄位 | 用途 |
|---|---|
| `id` | 本機資料識別碼 |
| `timestamp` | 偵測時間 |
| `maxDeltaT` | 最大溫差 |
| `maxRSSI` | 最大 RF 訊號強度 |
| `latitude` | GPS 緯度 |
| `longitude` | GPS 經度 |
| `statusColor` | `RED` 或 `YELLOW` |
| `userDecision` | 使用者複檢結果 |
| `adviceText` | 防護處置建議 |

資料模型加入基本限制：

```text
statusColor:
RED / YELLOW

userDecision:
CONFIRMED_DANGER / UNCERTAIN_WARNING
```

---

# 四、SQLite 與資料庫封裝

新增 `DatabaseHelper`，提供：

```dart
insertRecord(DetectionRecord record)
getAllRecords()
close()
```

原生平台使用 `sqflite`，建立 `detection_records` 資料表，並對以下欄位加入 SQLite CHECK constraint：

```sql
statusColor IN ('RED', 'YELLOW')

userDecision IN ('CONFIRMED_DANGER', 'UNCERTAIN_WARNING')
```

---

# 五、Safety Map 地圖頁

新增 `SafetyMapScreen`，使用：

- `flutter_map`
- `latlong2`
- OpenStreetMap 圖磚

## Marker 規則

| 顏色 | 代表狀態 |
|---|---|
| 紅色 Marker | 確認高風險事件 |
| 黃色 Marker | 待驗證疑慮事件 |

## Marker 點擊內容

點擊 Marker 後顯示 BottomSheet，內容包含：

- 偵測時間
- 溫差 `ΔT`
- RSSI 訊號強度
- 防護處置建議

Safety Map 已加入 App 主導覽列。

---

# 六、Flutter Web 無法啟動的問題與修復

## 問題一：總覽頁 Dart 編譯錯誤

原本將帶有 callback 的硬體卡片放在 `const` children list 中，造成：

```text
Invalid constant value
The values in a const list literal must be constants
Expected to find ')'
```

修復方式：

- 移除包含 callback 的 `const` list
- 只對不含 callback 的卡片使用 `const`
- 修正 `Card`、`InkWell` 與 `Padding` 括號結構

## 問題二：Web SQLite 依賴版本不相容

錯誤原因：

```text
sqflite_common_ffi_web >=1.1.2 requires Dart >=3.12.0
目前 Dart 版本為 3.11.5
```

後續處理：

- 移除不相容的 `sqflite_common_ffi_web`
- 將資料庫封裝改成平台分層
- Android / iOS 使用真正的 `sqflite`
- Web 使用暫時性的記憶體 fallback

## 問題三：Web services 平台差異

新增平台分層檔案：

```text
lib/services/database_helper.dart
lib/services/database_helper_native.dart
lib/services/database_helper_stub.dart
```

依平台條件匯入：

```dart
export 'database_helper_stub.dart'
    if (dart.library.io) 'database_helper_native.dart';
```

因此 Web 不會載入原生 SQLite API，也不會因 database factory 未初始化而在啟動時崩潰。

---

# 七、今日驗證結果

執行的驗證指令：

```bash
flutter pub get
flutter analyze
flutter build web --no-wasm-dry-run
```

結果：

```text
flutter pub get：成功
flutter analyze：No issues found!
flutter build web：成功產生 build/web
```

目前 Web 可使用以下指令啟動：

```powershell
C:\SDK\flutter\bin\flutter.bat run -d chrome --web-port 8080
```

---

# 八、目前尚未完成的項目

以下功能今天有規劃，但尚未完成正式實作：

- [ ] 高風險判定後自動取得 GPS
- [ ] 高風險或警示事件自動寫入 `DetectionRecord`
- [ ] 新增紀錄後即時刷新 Safety Map
- [ ] Web 使用 IndexedDB，讓資料在瀏覽器重整後保留
- [ ] 離線資料 outbox
- [ ] 網路恢復後同步雲端後端
- [ ] 離線地圖圖磚快取
- [ ] Safety Map 無資料時改用 Snackbar 或非阻擋式提示
- [ ] 實體 ESP32 BLE 封包與斷線重連測試
- [ ] BLE JSON 分包或二進位封包協定

---

# 九、今日結論

今日已完成 Flutter App 與 ESP32 BLE 硬體的基本資料串接，並建立 Safety Map 與資料模型的基礎架構。Web 版本曾因 `const`、依賴版本與 services 平台差異無法啟動，經修正後已通過靜態分析並成功產生 Web build。

目前系統已具備「硬體資料進入 App → 轉換為 ScanData → 顯示熱成像與風險分析 → 建立地圖資料基礎」的主要骨架。

下一階段重點是完成 GPS、自動事件寫入、Web 持久化與 Offline First 流程。
