#include <Arduino.h>
#include <ArduinoJson.h>
#include <NimBLEDevice.h>
#include <RadioLib.h>

// Install RadioLib, NimBLE-Arduino, and ArduinoJson from the Arduino Library
// Manager. Change these pins to match the ESP32 and CC1101 wiring.
constexpr int CC1101_CS = 5;
constexpr int CC1101_GDO0 = 4;
constexpr int CC1101_RST = 2;
constexpr int CC1101_GDO2 = 3;

constexpr char BLE_NAME[] = "CC1101_BLE";
constexpr char BLE_SERVICE_UUID[] =
    "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
constexpr char BLE_CHARACTERISTIC_UUID[] =
    "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

// RadioLib uses the ESP32 hardware SPI bus by default.
CC1101 radio = new Module(
    CC1101_CS,
    CC1101_GDO0,
    CC1101_RST,
    CC1101_GDO2
);

NimBLECharacteristic* diagnosticCharacteristic = nullptr;
volatile bool packetReady = false;
volatile bool bleConnected = false;

uint32_t receivedPackets = 0;
uint32_t lostPackets = 0;
uint32_t lastSequence = 0;
bool hasSequence = false;
float lastRssi = NAN;
int lastLqi = 0;
bool lastCrcOk = false;

class BleServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo&) override {
    bleConnected = true;
    Serial.println("BLE connected");
  }

  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
    bleConnected = false;
    Serial.println("BLE disconnected; restarting advertising");
    NimBLEDevice::startAdvertising();
  }
};

void IRAM_ATTR onPacketReceived() {
  packetReady = true;
}

void setupBle() {
  NimBLEDevice::init(BLE_NAME);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new BleServerCallbacks());
  NimBLEService* service = server->createService(BLE_SERVICE_UUID);
  diagnosticCharacteristic = service->createCharacteristic(
      BLE_CHARACTERISTIC_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
  );

  service->start();
  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(BLE_SERVICE_UUID);
  advertising->start();
}

void updatePacketCounters(const String& packet) {
  // The transmitter should send a decimal sequence number as the first field.
  // Example: "100,payload". Without sequence numbers, lostPackets stays zero.
  const int separator = packet.indexOf(',');
  if (separator <= 0) return;

  const uint32_t sequence = strtoul(packet.substring(0, separator).c_str(),
                                    nullptr,
                                    10);
  if (!hasSequence) {
    lastSequence = sequence;
    hasSequence = true;
    return;
  }

  if (sequence > lastSequence + 1) {
    lostPackets += sequence - lastSequence - 1;
  }
  if (sequence > lastSequence) {
    lastSequence = sequence;
  }
}

void notifyMetrics() {
  StaticJsonDocument<256> document;
  document["captured_at"] = millis();
  document["rssi"] = lastRssi;
  document["lqi"] = lastLqi;
  document["crc_ok"] = lastCrcOk;
  document["received_packets"] = receivedPackets;
  document["lost_packets"] = lostPackets;

  const uint32_t total = receivedPackets + lostPackets;
  document["per"] = total == 0
      ? 0.0
      : static_cast<float>(lostPackets) / static_cast<float>(total);

  String payload;
  serializeJson(document, payload);
  diagnosticCharacteristic->setValue(payload.c_str());
  diagnosticCharacteristic->notify();
}

void setup() {
  Serial.begin(115200);

  // Match these values to the transmitter's frequency and modulation.
  const int16_t state = radio.begin(433.0, 4.8, 5.0, 125.0, 10, 16);
  if (state != RADIOLIB_ERR_NONE) {
    Serial.printf("CC1101 init failed: %d\n", state);
    while (true) delay(1000);
  }

  setupBle();
  radio.setPacketReceivedAction(onPacketReceived);
  radio.startReceive();
  Serial.println("CC1101 BLE diagnostic ready");
}

void loop() {
  if (!packetReady) {
    delay(1);
    return;
  }

  noInterrupts();
  packetReady = false;
  interrupts();

  String packet;
  const int16_t state = radio.readData(packet);

  if (state == RADIOLIB_ERR_NONE) {
    receivedPackets++;
    lastRssi = radio.getRSSI();
    lastLqi = radio.getLQI();
    lastCrcOk = true;
    updatePacketCounters(packet);
    notifyMetrics();
    Serial.printf("RX: %s RSSI=%.1f LQI=%d\n",
                  packet.c_str(),
                  lastRssi,
                  lastLqi);
  } else if (state == RADIOLIB_ERR_CRC_MISMATCH) {
    lostPackets++;
    lastRssi = radio.getRSSI();
    lastLqi = radio.getLQI();
    lastCrcOk = false;
    notifyMetrics();
    Serial.println("CRC mismatch");
  } else {
    Serial.printf("CC1101 receive failed: %d\n", state);
  }

  radio.startReceive();
}
