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

---

# 2026-09-30 工作日誌補充

## 今日工作摘要

本次整理 App 主導覽與啟動平台設定，並處理 Web 頁面未顯示的問題。

## 主導覽與頁面切換

- 移除首頁 Dashboard，預設分頁改為「熱成像掃描」。
- 底部導覽列保留「熱成像」、「硬體監控」、「安全地圖」三項。
- Drawer 提供「熱成像」、「硬體監控」、「安全地圖」、「設定」、「關於」五項入口。
- 將 Drawer 項目的切換統一由 `_selectedIndex` 控制，並對應 `IndexedStack` 頁面順序。
- Drawer 關閉改用 `ScaffoldState.closeDrawer()`，避免用 `Navigator.pop(context)` 造成路由被彈出的風險。
- 設定與關於目前建立為空白頁；歷史紀錄模組保留，但不列入本次五個主要導覽項目。

## Web 與 Windows 平台

- 加入 Flutter Web 與 Windows 平台專案檔，建立時保留既有 Web 資產。
- 啟用 Flutter Windows 桌面開發設定。
- `flutter build web` 成功，產物位於 `build/web`。
- `flutter build windows` 成功，產物位於 `build/windows/x64/runner/Release/anti_pinhole.exe`。

## 驗證結果與待追蹤

```text
flutter analyze：No issues found
flutter test test/database_factory_test.dart：成功
flutter build web：成功
flutter build windows：成功
```

Web 專案建置成功，但透過 Chrome 啟動時工具曾逾時；使用 Web Server 模式啟動後，尚未確認瀏覽器頁面實際顯示。後續需確認 `flutter run -d web-server --web-port 8080` 完成啟動，並於 `http://localhost:8080` 驗證畫面。

---

# 2026-10-14 工作日誌｜SOP 高風險彈窗防重複與冷卻機制

## 今日工作摘要

修正 AntiPinhole App 在 CC1101、BLE 與熱成像感測器持續傳送高風險資料時，反覆呼叫 `showDialog` 所造成的彈窗無限堆疊、畫面卡死與記憶體耗用問題。

本次改為：

```text
高頻感測器資料
        ↓
更新畫面 / 熱圖 / 樣本列表
        ↓
高風險事件邊沿判定
        ↓
全域 Dialog 鎖 + 20 秒冷卻
        ↓
只顯示一個 SOP
        ↓
使用者選擇紅色或黃色處置
        ↓
寫入 SQLite DetectionRecord
```

---

## 一、原始問題與根因

### 問題現象

- 感測器約每幾百毫秒持續回傳資料。
- RSSI 或熱成像結果持續高於風險門檻。
- 每筆感測資料可能都有不同的 ID。
- 背景資料持續進入時，系統不斷呼叫 `showDialog`。
- 多個 Dialog 疊在 Navigator 上，最後造成畫面卡死或 App 崩潰。

### 根本原因

原本只使用單頁面的布林旗標或掃描 ID 判斷：

```dart
if (scan.analyze().isHighRisk && _alertScanId != scan.id) {
  showDialog(...);
}
```

但硬體資料每次可能產生新的 ID，因此即使仍是同一個持續高風險事件，也會被當成新的事件再次觸發。

另外，熱成像頁與 CC1101 診斷頁各自擁有自己的旗標，無法防止兩個頁面同時呼叫 Dialog。

---

## 二、SOP Dialog 全域防護

檔案：`lib/views/thermal/sop_dialog.dart`

新增全域顯示鎖與冷卻時間：

```dart
static bool _isShowing = false;
static DateTime? _lastClosedTime;
static const _cooldown = Duration(seconds: 20);
```

所有 SOP 顯示都必須通過同一個入口：

```dart
static Future<SopDecision?> show(BuildContext context) async {
  if (_isShowing) return null;

  final lastClosedTime = _lastClosedTime;
  if (lastClosedTime != null &&
      DateTime.now().difference(lastClosedTime) < _cooldown) {
    return null;
  }

  _isShowing = true;
  try {
    return await showDialog<SopDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: SopDialog(),
      ),
    );
  } finally {
    _isShowing = false;
    _lastClosedTime = DateTime.now();
  }
}
```

### 防護效果

| 防護條件 | 行為 |
|---|---|
| 已有 SOP 開啟 | 直接忽略新的觸發 |
| Dialog 剛關閉未滿 20 秒 | 不再次顯示 |
| 使用者按返回鍵 | 不允許繞過 SOP 狀態管理 |
| Dialog 發生例外 | `finally` 仍會釋放鎖並記錄關閉時間 |

---

## 三、二態處置流程

新增 SOP 結果：

```dart
enum SopDecision {
  confirmedDanger,
  uncertainWarning,
}
```

Dialog 提供兩個處置按鈕：

```dart
FilledButton(
  onPressed: () =>
      Navigator.of(context).pop(SopDecision.confirmedDanger),
  child: const Text('複檢異常'),
),
OutlinedButton(
  onPressed: () =>
      Navigator.of(context).pop(SopDecision.uncertainWarning),
  child: const Text('複檢正常（疑似誤判）'),
),
```

### 對照計畫書圖 2-1

| 使用者選擇 | SQLite 狀態 | 使用者決策 | 處置建議 |
|---|---|---|---|
| 複檢異常 | `RED` | `CONFIRMED_DANGER` | 立即檢查可疑位置並依安全程序處置 |
| 複檢正常 | `YELLOW` | `UNCERTAIN_WARNING` | 貼膠帶遮蔽或拔除電源後重新驗證 |

紀錄寫入核心邏輯：

```dart
final isDanger = decision == SopDecision.confirmedDanger;

await DatabaseHelper.instance.insertRecord(
  DetectionRecord(
    timestamp: DateTime.now().toUtc(),
    maxDeltaT: result.deltaT,
    maxRSSI: result.rssi,
    latitude: position.latitude,
    longitude: position.longitude,
    statusColor: isDanger ? 'RED' : 'YELLOW',
    userDecision:
        isDanger ? 'CONFIRMED_DANGER' : 'UNCERTAIN_WARNING',
    adviceText: isDanger
        ? '複檢異常：請立即檢查該位置並依現場安全程序處置。'
        : '複檢正常（疑似誤判）：建議貼膠帶遮蔽可疑位置或拔除電源後再驗證。',
  ),
);
```

---

## 四、高風險事件邊沿觸發

檔案：

```text
lib/views/thermal/thermal_scan_view.dart
lib/views/hardware/cc1101_diagnostic_view.dart
```

新增：

```dart
bool _isSopActive = false;
bool _riskEpisodeHandled = false;
DateTime? _lastSopClosedTime;
static const _sopCooldown = Duration(seconds: 20);
```

### 熱成像資料流程

```dart
final isHighRisk = scan.analyze().isHighRisk;

if (!isHighRisk) {
  _riskEpisodeHandled = false;
}

if (isHighRisk && !_riskEpisodeHandled) {
  _riskEpisodeHandled = true;
  _showSopForScan(scan);
}
```

### CC1101 RSSI 流程

```dart
final rssi = sample.rssi;

if (rssi == null || rssi <= _riskRssiThreshold) {
  _riskEpisodeHandled = false;
  return;
}

if (_riskEpisodeHandled) return;
if (_isSopActive) return;

final lastClosed = _lastSopClosedTime;
if (lastClosed != null &&
    DateTime.now().difference(lastClosed) < _sopCooldown) {
  return;
}

_riskEpisodeHandled = true;
_isSopActive = true;
```

### 事件狀態機

```text
SAFE / 低於門檻
        │
        ├── 高於門檻
        ▼
UNHANDLED HIGH RISK
        │
        ├── 顯示 SOP 一次
        ▼
HANDLED HIGH RISK
        │
        ├── 後續高風險資料只更新畫面
        │
        └── 必須回到 SAFE 才重新允許觸發
```

這代表即使 20 秒冷卻期結束，只要風險沒有降回安全狀態，也不會再次彈出 SOP。

---

## 五、背景資料更新策略

SOP 開啟期間不停止資料更新：

- 熱成像熱力圖持續更新。
- 最新風險文字持續更新。
- CC1101 原始樣本持續保存。
- 背景資料不會建立新的 Dialog。
- 使用者完成 SOP 後才寫入處置結果。

此方式避免使用者處理實體現場時，畫面資料停止更新，也避免用「暫停串流」掩蓋狀態管理問題。

---

## 六、異常與錯誤處理

若定位服務或定位權限不可用：

```dart
if (!await Geolocator.isLocationServiceEnabled()) {
  return false;
}
```

App 不會顯示「已成功記錄」的錯誤訊息，而會明確提示：

```text
定位服務不可用，無法寫入事件紀錄
```

Dialog 的鎖定狀態使用 `finally` 釋放，確保即使資料庫寫入或定位流程發生例外，也不會永久卡住 SOP。

---

## 七、修改檔案

| 檔案 | 修改內容 |
|---|---|
| `lib/views/thermal/sop_dialog.dart` | 全域 Dialog 鎖、20 秒冷卻、二態處置結果 |
| `lib/views/thermal/thermal_scan_view.dart` | 熱成像高風險事件邊沿觸發、SQLite 處置紀錄 |
| `lib/views/hardware/cc1101_diagnostic_view.dart` | CC1101 RSSI 事件鎖定、SQLite 處置紀錄與錯誤提示 |

---

## 八、驗證結果

### 靜態分析

```text
flutter analyze \
  lib/views/thermal/sop_dialog.dart \
  lib/views/thermal/thermal_scan_view.dart \
  lib/views/hardware/cc1101_diagnostic_view.dart

No issues found!
```

### 聚焦測試

```text
flutter test \
  test/database_factory_test.dart \
  test/cc1101_diagnostic_sample_test.dart \
  test/thermal_heatmap64_view_test.dart

6 tests passed
```

### 已知既有問題

全專案分析仍有一個原有測試錯誤：

```text
test/widget_test.dart 使用不存在的 MyApp
目前實際 App 類別為 AntiPinholeApp
```

此問題與本次 SOP 防重複邏輯修改無關，尚未在本次日誌中一併變更。

---

## 九、今日結論

本次已將 SOP 觸發從「每筆高風險資料都可能觸發」改為：

```text
單一全域 Dialog
+ Dialog 顯示鎖
+ 20 秒冷卻
+ 高風險事件邊沿觸發
+ 風險解除後才重新 armed
+ 二態處置結果寫入 SQLite
```

因此，持續高風險資料只會更新監控畫面，不會再無限堆疊彈窗。下一步建議使用實際 CC1101、BLE 與熱成像硬體進行長時間壓力測試，確認在高頻資料持續輸入下 Navigator 與記憶體使用量保持穩定。

---

# 2026-10-21 工作日誌｜SOP 非阻塞卡片、異常快照凍結與 CC1101 偵測暫停

> 專案：AntiPinhole Detector 反針孔與熱成像偵測 App  
> 今日主題：讓使用者可以在 SOP 出現時辨識異常位置，並避免全畫面彈窗與持續資料更新造成干擾

---

## 一、需求背景

使用者在熱成像或 CC1101 偵測到異常後，需要先辨識異常位置，再進行現場光學複檢。

原本的問題有兩個：

1. SOP 使用全畫面 Modal Dialog，會遮住熱力圖與硬體資料。
2. SOP 出現後硬體資料仍持續更新，熱點、RSSI 與原始紀錄會一直變動，使用者不容易確認是哪一次資料造成異常。

本次調整目標：

```text
異常觸發
    ↓
保存觸發當下快照
    ↓
暫停偵測／畫面更新 10 秒
    ↓
顯示底部非阻塞式 SOP 卡片
    ↓
使用者辨識異常位置並進行光學複檢
    ↓
10 秒後恢復即時偵測
    ↓
使用者完成分案後啟動 20 秒新異常提示冷卻
```

---

## 二、SOP UI 改為非阻塞式底部卡片

### 原本行為

熱成像與 CC1101 都透過 `SopDialog.show()` 顯示全畫面 Dialog：

```text
showDialog
    ↓
Modal barrier 覆蓋整個頁面
    ↓
使用者無法同時查看與操作背景資料
```

### 修改後行為

兩個頁面統一使用共用的 `SopCard`：

```text
Stack
├── 即時偵測頁面
└── Positioned(bottom: 20)
    └── SopCard
```

SOP 卡片功能：

- 顯示在頁面底部，不遮住整個熱力圖或監控畫面。
- 顯示觸發當下的 RSSI 與熱成像 ΔT。
- 支援展開與收合。
- 收合後保留「高風險 SOP 進行中」提示列。
- 使用者選擇「複檢異常」或「複檢正常」後才完成本次 SOP。
- 收合不等於完成，也不會啟動 20 秒冷卻。

共用元件位置：

```text
lib/views/thermal/sop_dialog.dart
```

雖然檔名仍保留 `sop_dialog.dart`，但 `SopCard` 已作為熱成像與 CC1101 共用的非阻塞 UI 元件。

---

## 三、異常觸發快照凍結 10 秒

### 熱成像頁

熱成像頁在高風險觸發時：

- 保存當下的 `ScanData` 與 64×64 熱力圖。
- 畫面保持觸發當下的熱力圖、ΔT 與 RSSI。
- 後續收到的資料暫存在 `_latestScanDuringFreeze`。
- SOP 卡片顯示剩餘凍結秒數。
- 10 秒結束後使用最新資料恢復即時畫面。
- 不清除熱力圖，也不斷開 ThermoCam 或 ESP32 連線。

相關狀態：

```dart
Timer? _snapshotFreezeTimer;
DateTime? _snapshotFreezeUntil;
ScanData? _latestScanDuringFreeze;
```

### CC1101 頁

CC1101 頁也加入相同的 10 秒快照凍結流程：

- 保存觸發當下的 `Cc1101DiagnosticSample`。
- 凍結期間不更新 RSSI、指標與原始紀錄列表。
- 後續收到的封包暫存在 `_latestSampleDuringFreeze`。
- 倒數結束後加入最新封包並恢復更新。

---

## 四、CC1101 真正暫停硬體偵測

初版 CC1101 只暫停畫面更新，但 service 仍然持續收資料，因此 SOP 出現時硬體仍在偵測。

本次改為在 service 層提供真正的暫停／恢復 API：

```dart
Future<void> pauseDetection()
Future<void> resumeDetection()
```

### Wi-Fi / HTTP 模式

```text
pauseDetection()
    ↓
停止 500 ms HTTP polling Timer

resumeDetection()
    ↓
重新建立 polling Timer
```

### Bluetooth BLE 模式

```text
pauseDetection()
    ↓
取消 BLE value subscription
停止 notification
保留 BLE 連線

resumeDetection()
    ↓
重新開啟 notification
重新建立 value subscription
```

這樣可以讓硬體停止產生新的偵測資料，但不需要在 10 秒後重新掃描、配對或建立連線。

相關檔案：

```text
lib/services/cc1101_diagnostic_service.dart
lib/views/hardware/cc1101_diagnostic_view.dart
```

---

## 五、20 秒分案後冷卻機制

10 秒快照凍結與 20 秒冷卻是兩個不同用途：

| 時間 | 觸發時間點 | 目的 |
|---|---|---|
| 10 秒快照凍結 | 偵測到異常時 | 讓使用者辨識異常位置 |
| 20 秒新 SOP 冷卻 | 使用者完成分案時 | 避免下一個異常立即打斷使用者 |

完整行為：

```text
高風險觸發
    ↓
凍結快照 10 秒
    ↓
恢復硬體偵測
    ↓
使用者可繼續查看即時資料與完成 SOP
    ↓
按下複檢結果
    ↓
開始 20 秒新 SOP 冷卻
```

以下情況不會啟動 20 秒冷卻：

- SOP 卡片收合。
- SOP 卡片展開。
- 10 秒快照倒數結束。
- 使用者尚未選擇複檢結果。

---

## 六、風險事件防重複

兩個頁面都保留高風險事件邊沿觸發：

```text
安全
  ↓
第一次高風險：顯示 SOP
  ↓
高風險持續中：不重複觸發
  ↓
恢復安全：重新 armed
  ↓
再次高風險：允許新 SOP
```

因此：

- 10 秒凍結不會建立多個 SOP。
- SOP 顯示期間不會重複開啟新的卡片。
- 使用者分案後 20 秒內不會再次顯示新的 SOP。
- 同一段持續高風險不會每 20 秒重複提示。

---

## 七、驗證結果

### Dart 靜態分析

```bash
flutter analyze \
  lib/services/cc1101_diagnostic_service.dart \
  lib/views/hardware/cc1101_diagnostic_view.dart
```

結果：

```text
No issues found!
```

### 相關測試

```bash
flutter test \
  test/cc1101_diagnostic_sample_test.dart \
  test/thermal_heatmap64_view_test.dart
```

結果：

```text
5 tests passed
```

---

## 八、修改檔案摘要

| 檔案 | 修改內容 |
|---|---|
| `lib/views/thermal/sop_dialog.dart` | 新增共用非阻塞 `SopCard`，支援收合、快照提示與複檢結果 |
| `lib/views/thermal/thermal_scan_view.dart` | 熱成像異常快照凍結 10 秒，恢復後套用最新資料 |
| `lib/views/hardware/cc1101_diagnostic_view.dart` | CC1101 SOP 卡片、10 秒快照凍結與分案後冷卻 |
| `lib/services/cc1101_diagnostic_service.dart` | 新增 CC1101 偵測暫停／恢復，支援 HTTP 與 BLE |

---

## 九、今日結論

本次完成後，熱成像與 CC1101 的 SOP 行為統一為：

```text
非阻塞底部 SOP 卡片
+ 觸發當下異常快照
+ 10 秒偵測暫停／畫面凍結
+ 10 秒後自動恢復
+ 使用者完成分案後 20 秒冷卻
+ 高風險事件邊沿觸發
+ 風險解除後重新 armed
```

使用者可以先看清楚異常位置，再進行現場光學複檢；同時也能避免全畫面彈窗遮擋資料，以及高頻硬體資料造成畫面持續跳動。
