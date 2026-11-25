/*
 * ============================================================
 *  ESP32-C5 AntiPinhole 多模態防針孔系統 — 完整整合版
 * ============================================================
 *  - 硬體腳位：採用檔案 2 配置 + GPIO1 (940nm IR LED)
 *  - 感測模組：
 *      1. AMG8833 (I2C: SDA=8, SCL=9) 8x8 熱成像 + 異常高溫偵測
 *      2. CC1101  (SPI: SCK=6, MISO=2, MOSI=7, CS=10, GDO0=3) 433.92MHz 封包與環境 RSSI
 *      3. VS1838B (GPIO 4) + 940nm LED (GPIO 1, 10Hz) 雙模 IR 偵測
 *      4. Wi-Fi   背景掃描 + 卡爾曼濾波距離估算 + UDP 廣播 (Port 4212)
 *      5. BLE     NimBLE Server (20-byte 分段 JSON Notify) + 被動 BLE 裝置計數
 * ============================================================
 */

#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <Adafruit_AMG88xx.h>
#include <RadioLib.h>
#include <IRremote.hpp>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>
#include <math.h>
#include <map>

// ==================== 1. 硬體腳位定義 (以檔案 2 為主) ====================
constexpr int I2C_SDA_PIN     = 8;
constexpr int I2C_SCL_PIN     = 9;

constexpr int CC1101_SCK_PIN  = 6;
constexpr int CC1101_MISO_PIN = 2;
constexpr int CC1101_MOSI_PIN = 7;
constexpr int CC1101_CS_PIN   = 10;
constexpr int CC1101_GDO0_PIN = 3;

constexpr int IR_RX_PIN       = 4;
constexpr int IR_LED_PIN      = 1;   // 940nm LED -> 220Ω -> GND (10Hz 閃爍)

// ==================== 2. Wi-Fi / UDP / BLE 參數 ====================
const char* WIFI_SSID     = "";
const char* WIFI_PASS     = "";
const char* UDP_TARGET_IP = "";      // 留空 = 區網廣播
const int   UDP_PORT      = 4212;

constexpr char BLE_NAME[]                = "CC1101_BLE";
constexpr char BLE_SERVICE_UUID[]        = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
constexpr char BLE_CHARACTERISTIC_UUID[] = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
constexpr size_t BLE_NOTIFICATION_CHUNK_SIZE = 20;

// ==================== 3. 熱成像與 Wi-Fi 測距常數 ====================
const float TEMP_OFFSET        = -2.0f;
const float OVERHEAT_THRESHOLD = 36.0f;
#define SIMULATE_WHEN_NO_AMG 0       // 1 = 無硬體時輸出模擬數據，0 = 實際狀態

const float A_1M_RSSI   = -55.0f;
const float PATH_LOSS_N = 2.5f;
const unsigned long SCAN_GAP_MS = 2500;

// ==================== 4. 模組實例與全域狀態 ====================
CC1101 radio = new Module(CC1101_CS_PIN, CC1101_GDO0_PIN, RADIOLIB_NC, RADIOLIB_NC);
Adafruit_AMG88xx amg;
WiFiUDP udp;

NimBLECharacteristic* diagnosticCharacteristic = nullptr;
NimBLEScan* pBLEScan = nullptr;

// RF 狀態
volatile bool rfPacketReady = false;
bool radioAvailable = false;
uint32_t receivedPackets = 0;
uint32_t lostPackets = 0;
float lastRssi = 0.0f;
bool hasRssi = false;
bool hasEnvironmentRssi = false;
int lastLqi = 0;
bool lastCrcOk = false;
bool rfDetected = false;

// 熱成像狀態
float thermalPixels[AMG88xx_PIXEL_ARRAY_SIZE];
bool thermalAvailable = false;
bool thermalSimulated = false;
float lastMaxTemperature = 0.0f;
float lastDeltaTemp = 0.0f;
uint32_t lastAmgRetry = 0;

// IR 狀態 (支援脈衝計數 + 協定解碼)
volatile unsigned long irPulseCount = 0;
unsigned int irPulseHistory[3] = {0, 0, 0};
byte irHistoryIdx = 0;
uint32_t lastIrBlinkTime = 0;
bool irLedState = false;
bool irDetected = false;
uint32_t lastIrCode = 0;
String lastIrProtocol = "";

// Wi-Fi 與 BLE 掃描狀態
volatile bool bleConnected = false;
volatile int bleDevicesFound = 0;
uint32_t lastBLEScanTime = 0;
uint32_t lastWifiRetry = 0;
uint32_t lastScanDone = 0;
int wifiApCount = 0;
bool wifiResultsProcessed = true;

// ==================== 5. 卡爾曼濾波器 ====================
class KalmanFilter {
 private:
  float Q, R, P, X;
  bool initialized;
 public:
  KalmanFilter(float q = 0.1f, float r = 4.0f)
      : Q(q), R(r), P(1.0f), X(0.0f), initialized(false) {}

  float update(float m) {
    if (!initialized) {
      X = m;
      initialized = true;
      return X;
    }
    P = P + Q;
    float K = P / (P + R);
    X = X + K * (m - X);
    P = (1.0f - K) * P;
    return X;
  }
  float value() const { return X; }
};

std::map<String, KalmanFilter> kalmanMap;

float rssiToDistance(float rssi) {
  if (rssi >= 0.0f) return -1.0f;
  return pow(10.0f, (A_1M_RSSI - rssi) / (10.0f * PATH_LOSS_N));
}

// ==================== 6. 中斷與 BLE 回呼 ====================
void IRAM_ATTR onRfPacketReceived() {
  rfPacketReady = true;
}

void IRAM_ATTR onIrPulse() {
  irPulseCount++;
}

class ServerCallbacks : public NimBLEServerCallbacks {
 public:
  void onConnect(NimBLEServer* server, NimBLEConnInfo& connInfo) override {
    bleConnected = true;
    Serial.println("[BLE] App connected");
  }

  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& connInfo, int reason) override {
    bleConnected = false;
    Serial.printf("[BLE] App disconnected, reason: %d\n", reason);
    NimBLEDevice::startAdvertising();
  }
};

class ScanCallbacks : public NimBLEScanCallbacks {
 public:
  void onScanEnd(const NimBLEScanResults& results, int reason) override {
    bleDevicesFound = results.getCount();
  }
};

// ==================== 7. 初始化函式 ====================
void setupBle() {
  NimBLEDevice::init(BLE_NAME);
  NimBLEDevice::setDeviceName(BLE_NAME);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  NimBLEService* service = server->createService(BLE_SERVICE_UUID);
  diagnosticCharacteristic = service->createCharacteristic(
      BLE_CHARACTERISTIC_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
  );
  diagnosticCharacteristic->setValue("{}");
  service->start();

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData advertisementData;
  advertisementData.setFlags(0x06);
  advertisementData.setName(BLE_NAME);

  NimBLEAdvertisementData scanResponseData;
  scanResponseData.addServiceUUID(BLE_SERVICE_UUID);

  advertising->setAdvertisementData(advertisementData);
  advertising->setScanResponseData(scanResponseData);
  advertising->enableScanResponse(true);
  // 稍微放寬廣播間隔以確保與 Wi-Fi 掃描並存時的穩定度
  advertising->setMinInterval(48);
  advertising->setMaxInterval(96);
  advertising->start();

  pBLEScan = NimBLEDevice::getScan();
  pBLEScan->setScanCallbacks(new ScanCallbacks(), false);
  pBLEScan->setActiveScan(false);
  pBLEScan->setInterval(100);
  pBLEScan->setWindow(99);

  Serial.printf("[OK] BLE Advertising started as %s\n", BLE_NAME);
}

bool initAMG8833() {
  if (amg.begin(0x69, &Wire)) return true;
  if (amg.begin(0x68, &Wire)) return true;
  return false;
}

void setupThermalSensor() {
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setClock(100000);
  thermalAvailable = initAMG8833();
  Serial.println(thermalAvailable ? "[OK] AMG8833 initialized" : "[WARN] AMG8833 not found, will retry");
}

void setupRadio() {
  SPI.begin(CC1101_SCK_PIN, CC1101_MISO_PIN, CC1101_MOSI_PIN, CC1101_CS_PIN);

  ConfigFSK_t config;
  config.frequency = 433920000;
  config.bitRate = 4800;
  config.frequencyDeviation = 48000;
  config.receiverBandwidth = 135000;
  config.power = 10;
  config.preambleLength = 32;

  const int16_t state = radio.begin(config);
  if (state != RADIOLIB_ERR_NONE) {
    radioAvailable = false;
    Serial.printf("[ERROR] CC1101 init failed: %d\n", state);
    return;
  }

  radioAvailable = true;
  radio.setGdo0Action(onRfPacketReceived, RISING);
  radio.startReceive();
  Serial.printf("[OK] CC1101 initialized (Chip v0x%02X)\n", radio.getChipVersion());
}

void setupIr() {
  pinMode(IR_LED_PIN, OUTPUT);
  digitalWrite(IR_LED_PIN, LOW);

  // 啟動 IRremote 接收並掛載中斷計數（偵測非協定純紅外線脈衝）
  IrReceiver.begin(IR_RX_PIN, DISABLE_LED_FEEDBACK);
  attachInterrupt(digitalPinToInterrupt(IR_RX_PIN), onIrPulse, FALLING);
  Serial.printf("[OK] IR RX on GPIO %d, 940nm LED on GPIO %d\n", IR_RX_PIN, IR_LED_PIN);
}

void setupWiFi() {
  WiFi.mode(WIFI_STA);
  if (WIFI_SSID[0] == '\0') {
    Serial.println("[INFO] Wi-Fi credentials are unset; AP scanning works, UDP is disabled");
    return;
  }

  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Connecting Wi-Fi");
  for (int i = 0; i < 16 && WiFi.status() != WL_CONNECTED; i++) {
    delay(500);
    Serial.print(".");
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[OK] Wi-Fi connected, IP: " + WiFi.localIP().toString());
  } else {
    Serial.println("\n[WARN] Wi-Fi timeout, retrying in background");
  }
}

// ==================== 8. 感測器輪詢與分析 ====================
void updateThermal() {
  static uint32_t lastRead = 0;
  if (millis() - lastRead < 250) return;
  lastRead = millis();

  thermalSimulated = false;
  if (!thermalAvailable && millis() - lastAmgRetry >= 5000) {
    lastAmgRetry = millis();
    thermalAvailable = initAMG8833();
  }

  if (thermalAvailable) {
    amg.readPixels(thermalPixels);
  } else {
#if SIMULATE_WHEN_NO_AMG
    thermalSimulated = true;
    for (size_t i = 0; i < AMG88xx_PIXEL_ARRAY_SIZE; i++) {
      thermalPixels[i] = 25.0f + ((rand() % 20) / 10.0f - 1.0f);
    }
    thermalPixels[27] = 36.5f;
#else
    return;
#endif
  }

  float max1 = -100.0f, max2 = -100.0f, sum = 0.0f;
  int valid = 0;

  for (size_t i = 0; i < AMG88xx_PIXEL_ARRAY_SIZE; i++) {
    if (!thermalSimulated) {
      thermalPixels[i] += TEMP_OFFSET;
    }
    float t = thermalPixels[i];
    if (t >= 0.0f && t <= 80.0f) {
      sum += t;
      valid++;
      if (t > max1) {
        max2 = max1;
        max1 = t;
      } else if (t > max2) {
        max2 = t;
      }
    }
  }

  if (valid > 10) {
    lastMaxTemperature = max1;
    lastDeltaTemp = max2 - (sum / valid);
  } else {
    lastMaxTemperature = thermalPixels[0];
    lastDeltaTemp = 0.0f;
  }
}

void processRf() {
  if (!radioAvailable || !rfPacketReady) return;

  noInterrupts();
  rfPacketReady = false;
  interrupts();

  String receivedData;
  const int16_t state = radio.readData(receivedData);

  if (state == RADIOLIB_ERR_NONE) {
    receivedPackets++;
    lastRssi = radio.getRSSI();
    lastLqi = radio.getLQI();
    lastCrcOk = true;
    hasRssi = true;
    rfDetected = true;
  } else if (state == RADIOLIB_ERR_CRC_MISMATCH) {
    lostPackets++;
    lastRssi = radio.getRSSI();
    lastLqi = radio.getLQI();
    lastCrcOk = false;
    hasRssi = true;
    rfDetected = true;
  } else {
    rfDetected = false;
  }

  radio.startReceive();
}

void updateEnvironmentRssi() {
  if (!radioAvailable) return;

  static uint32_t lastRssiRead = 0;
  if (millis() - lastRssiRead < 500) return;
  lastRssiRead = millis();

  radio.receiveDirectAsync();
  const float rssi = radio.getRSSI();
  radio.packetMode();
  radio.startReceive();

  if (rssi >= -150.0f && rssi <= 20.0f) {
    lastRssi = rssi;
    hasEnvironmentRssi = true;
  }
}

void processIr() {
  // 1. 嘗試解碼標準遙控器協定 (檔案 2 邏輯)
  if (IrReceiver.decode()) {
    if (IrReceiver.decodedIRData.protocol != UNKNOWN) {
      irDetected = true;
      lastIrCode = IrReceiver.decodedIRData.decodedRawData;
      lastIrProtocol = getProtocolString(IrReceiver.decodedIRData.protocol);
    }
    IrReceiver.resume();
  }

  // 2. 每 500ms 統計純紅外線脈衝數，偵測鏡頭反射或無協定紅外線補光燈 (檔案 1 邏輯)
  static uint32_t lastPulseCheck = 0;
  if (millis() - lastPulseCheck >= 500) {
    lastPulseCheck = millis();

    noInterrupts();
    unsigned long count = irPulseCount;
    irPulseCount = 0;
    interrupts();

    irPulseHistory[irHistoryIdx] = count;
    irHistoryIdx = (irHistoryIdx + 1) % 3;

    int hitCount = 0;
    for (int i = 0; i < 3; i++) {
      if (irPulseHistory[i] >= 2) hitCount++;
    }

    if (count >= 30 || hitCount >= 2) {
      irDetected = true;
      if (lastIrProtocol.length() == 0) {
        lastIrProtocol = "RAW_PULSE";
      }
    }
  }
}

void handleWifi() {
  uint32_t now = millis();

  if (WIFI_SSID[0] != '\0' &&
      WiFi.status() != WL_CONNECTED &&
      now - lastWifiRetry >= 10000) {
    lastWifiRetry = now;
    WiFi.reconnect();
  }

  int r = WiFi.scanComplete();
  if (r >= 0 && !wifiResultsProcessed) {
    wifiApCount = r;
    for (int i = 0; i < r; ++i) {
      int rawRssi = WiFi.RSSI(i);
      if (rawRssi < -98) continue;
      kalmanMap[WiFi.BSSIDstr(i)].update((float)rawRssi);
    }
    wifiResultsProcessed = true;
    lastScanDone = now;
  }

  if (r != WIFI_SCAN_RUNNING &&
      wifiResultsProcessed &&
      now - lastScanDone >= SCAN_GAP_MS) {
    if (r >= 0) WiFi.scanDelete();
    WiFi.scanNetworks(true, true, false, 120);
    wifiResultsProcessed = false;
    lastScanDone = now;
  }
}

// ==================== 9. 數據封裝與傳送 (BLE 分段 JSON + UDP) ====================
void buildDiagnosticJson(String& outPayload) {
  JsonDocument document;

  document["captured_at"] = millis();
  document["device_name"] = BLE_NAME;
  document["rf_detected"] = rfDetected;

  // CC1101 數據 (完整保留檔案 2 鍵值)
  if (hasRssi || hasEnvironmentRssi) {
    document["rf_rssi"] = lastRssi;
    document["rf"] = lastRssi;
    document["rssi"] = lastRssi;
  } else {
    document["rf_rssi"] = nullptr;
    document["rf"] = nullptr;
    document["rssi"] = nullptr;
  }

  if (hasRssi) {
    document["lqi"] = lastLqi;
    document["crc_ok"] = lastCrcOk;
  } else {
    document["lqi"] = nullptr;
    document["crc_ok"] = nullptr;
  }

  const uint32_t totalPackets = receivedPackets + lostPackets;
  float per = totalPackets == 0 ? 0.0f : static_cast<float>(lostPackets) / static_cast<float>(totalPackets);

  JsonObject cc1101 = document["cc1101"].to<JsonObject>();
  if (hasRssi || hasEnvironmentRssi) {
    cc1101["rssi"] = lastRssi;
  } else {
    cc1101["rssi"] = nullptr;
  }
  if (hasRssi) {
    cc1101["lqi"] = lastLqi;
    cc1101["crc_ok"] = lastCrcOk;
  } else {
    cc1101["lqi"] = nullptr;
    cc1101["crc_ok"] = nullptr;
  }
  cc1101["received_packets"] = receivedPackets;
  cc1101["lost_packets"] = lostPackets;
  cc1101["per"] = per;

  document["received_packets"] = receivedPackets;
  document["lost_packets"] = lostPackets;
  document["per"] = per;

  // AMG8833 熱成像數據
  if (!thermalAvailable && !thermalSimulated) {
    document["thermal"] = nullptr;
    document["max_temp"] = nullptr;
  } else {
    JsonArray thermal = document["thermal"].to<JsonArray>();
    JsonArray amgPixels = document["amg8833"]["pixels"].to<JsonArray>();
    for (size_t i = 0; i < AMG88xx_PIXEL_ARRAY_SIZE; i++) {
      float rounded = roundf(thermalPixels[i] * 10.0f) / 10.0f;
      thermal.add(rounded);
      amgPixels.add(rounded);
    }
    document["max_temp"] = roundf(lastMaxTemperature * 10.0f) / 10.0f;
  }

  // IR 紅外線數據
  document["ir"] = irDetected;
  document["ir_detected"] = irDetected;
  if (irDetected) {
    document["ir_protocol"] = lastIrProtocol;
    if (lastIrCode != 0) {
      char irCode[12];
      snprintf(irCode, sizeof(irCode), "%lX", static_cast<unsigned long>(lastIrCode));
      document["ir_code"] = irCode;
    } else {
      document["ir_code"] = "PULSE";
    }
  } else {
    document["ir_protocol"] = nullptr;
    document["ir_code"] = nullptr;
  }

  // 新增：Wi-Fi 卡爾曼掃描清單與 BLE 裝置數 (來自檔案 1)
  document["wifi_count"] = wifiApCount;
  document["ble_count"] = (int)bleDevicesFound;

  JsonArray wifiList = document["wifi_networks"].to<JsonArray>();
  int scanResult = WiFi.scanComplete();
  if (scanResult > 0) {
    // 限制最多前 8 筆最強訊號，避免 JSON 過大導致 20-byte 分段傳送耗時過久
    int limit = min(scanResult, 8);
    for (int i = 0; i < limit; i++) {
      if (WiFi.RSSI(i) < -98) continue;
      String bssid = WiFi.BSSIDstr(i);
      float filteredRssi = kalmanMap[bssid].value();
      if (filteredRssi == 0.0f) filteredRssi = WiFi.RSSI(i);

      JsonObject ap = wifiList.add<JsonObject>();
      String ssid = WiFi.SSID(i);
      ap["ssid"] = ssid.length() > 0 ? ssid.substring(0, 20) : "[Hidden]";
      ap["rssi"] = roundf(filteredRssi * 10.0f) / 10.0f;
      ap["distance_m"] = roundf(rssiToDistance(filteredRssi) * 10.0f) / 10.0f;
    }
  }

  serializeJson(document, outPayload);
}

void sendBleChunkedJson(const String& payload) {
  if (!bleConnected || diagnosticCharacteristic == nullptr) return;

  const uint8_t* bytes = reinterpret_cast<const uint8_t*>(payload.c_str());
  const size_t length = payload.length();
  bool notified = true;

  for (size_t offset = 0; offset < length; offset += BLE_NOTIFICATION_CHUNK_SIZE) {
    const size_t remaining = length - offset;
    const size_t chunkLength = remaining < BLE_NOTIFICATION_CHUNK_SIZE ? remaining : BLE_NOTIFICATION_CHUNK_SIZE;

    if (!diagnosticCharacteristic->notify(bytes + offset, chunkLength)) {
      notified = false;
      break;
    }
    delay(4);
  }

  Serial.printf("[BLE TX] bytes=%u notify=%s\n", (unsigned int)length, notified ? "OK" : "FAIL");
}

void sendUdpJson(const String& payload) {
  if (WiFi.status() != WL_CONNECTED) return;

  IPAddress target;
  if (strlen(UDP_TARGET_IP) == 0 || !target.fromString(UDP_TARGET_IP)) {
    target = WiFi.broadcastIP();
  }

  udp.beginPacket(target, UDP_PORT);
  udp.write(reinterpret_cast<const uint8_t*>(payload.c_str()), payload.length());
  udp.endPacket();
}

// ==================== 10. 主程式進入點 ====================
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=== AntiPinhole ESP32-C5 (Merged Edition) ===");

  setupBle();
  setupThermalSensor();
  setupRadio();
  setupIr();
  setupWiFi();

  Serial.println("[OK] All subsystems initialized");
}

void loop() {
  uint32_t now = millis();

  // 1. 940nm 紅外線 LED 10Hz 閃爍 (每 50ms 切換狀態)
  if (now - lastIrBlinkTime >= 50) {
    lastIrBlinkTime = now;
    irLedState = !irLedState;
    digitalWrite(IR_LED_PIN, irLedState);
  }

  // 2. 感測器資料更新
  processRf();
  processIr();
  updateThermal();
  updateEnvironmentRssi();
  handleWifi();

  // 3. 未連線時背景掃描周遭 BLE 裝置數量
  if (!bleConnected && pBLEScan != nullptr && !pBLEScan->isScanning() && now - lastBLEScanTime >= 5000) {
    lastBLEScanTime = now;
    pBLEScan->start(1000, false);
  }

  // 4. 每 1000ms 打包並發送 JSON (BLE 分段 + UDP)
  static uint32_t lastBleUpdate = 0;
  if (now - lastBleUpdate >= 1000) {
    lastBleUpdate = now;

    String jsonPayload;
    buildDiagnosticJson(jsonPayload);

    sendBleChunkedJson(jsonPayload);
    sendUdpJson(jsonPayload);

    // 重置單次觸發旗標
    rfDetected = false;
    irDetected = false;
    lastIrCode = 0;
    lastIrProtocol = "";
  }

  delay(2);
}