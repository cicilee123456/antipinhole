/*
  Anti-Pinhole ESP32 sensor gateway

  Board: ESP32-C5-DevKitC-1 v1.1

  Pin map:
    AMG8833       VIN -> 3V3, GND -> GND, SDA -> GPIO2, SCL -> GPIO3
    VS1838B      VCC -> 3V3, GND -> GND, OUT -> GPIO10
    CC1101       VCC -> 3V3, GND -> GND
                  SCK -> GPIO4, MISO -> GPIO5, MOSI -> GPIO6
                  CSN/SS -> GPIO7, GDO0 -> GPIO8
                  GDO2 -> GPIO9

  The ESP32 starts an access point:
    SSID: AntiPinhole-ESP32
    password: antipinhole
    endpoint: http://192.168.4.1/data

  Install these libraries from Arduino Library Manager:
    Adafruit AMG88xx
    ArduinoJson
    RadioLib
    IRremoteESP8266
*/

#include <Adafruit_AMG88xx.h>
#include <Arduino.h>
#include <ArduinoJson.h>
#include <IRrecv.h>
#include <IRutils.h>
#include <RadioLib.h>
#include <SPI.h>
#include <WebServer.h>
#include <WiFi.h>
#include <Wire.h>

constexpr int I2C_SDA = 2;
constexpr int I2C_SCL = 3;
constexpr int VS1838B_PIN = 10;

constexpr int CC1101_SCK = 4;
constexpr int CC1101_MISO = 5;
constexpr int CC1101_MOSI = 6;
constexpr int CC1101_CS = 7;
constexpr int CC1101_GDO0 = 8;
constexpr int CC1101_GDO2 = 9;

constexpr char AP_SSID[] = "AntiPinhole-ESP32";
constexpr char AP_PASSWORD[] = "antipinhole";

Adafruit_AMG88xx amg;
IRrecv irrecv(VS1838B_PIN);
decode_results irResults;

CC1101 radio = new Module(
    CC1101_CS,
    CC1101_GDO0,
    -1,
    CC1101_GDO2
);
WebServer server(80);

float thermalPixels[64];
bool thermalReady = false;
bool radioReady = false;
float lastRfRssi = -100.0;
int lastLqi = 0;
bool lastCrcOk = false;
uint32_t receivedPackets = 0;
uint32_t lostPackets = 0;
String lastIrCode;
String lastIrProtocol;
bool irDetected = false;
uint32_t irDetectedAt = 0;
volatile bool packetReady = false;

void onRadioPacket() {
  packetReady = true;
}

void readInfrared() {
  if (irrecv.decode(&irResults)) {
    irDetected = true;
    irDetectedAt = millis();
    lastIrCode = uint64ToString(irResults.value, 16);
    lastIrProtocol = typeToString(irResults.decode_type);
    irrecv.resume();
  }
  if (millis() - irDetectedAt > 1500) {
    irDetected = false;
  }
}

void readRadio() {
  if (!radioReady) {
    return;
  }
  if (!packetReady) {
    return;
  }
  noInterrupts();
  packetReady = false;
  interrupts();

  String packet;
  const int16_t state = radio.readData(packet);
  if (state == RADIOLIB_ERR_NONE) {
    receivedPackets++;
    lastRfRssi = radio.getRSSI();
    lastLqi = radio.getLQI();
    lastCrcOk = true;
  } else if (state == RADIOLIB_ERR_CRC_MISMATCH) {
    lostPackets++;
    lastRfRssi = radio.getRSSI();
    lastLqi = radio.getLQI();
    lastCrcOk = false;
  }
  radio.startReceive();
}

void readThermal() {
  if (thermalReady) {
    amg.readPixels(thermalPixels);
  }
}

void handleData() {
  readThermal();

  DynamicJsonDocument document(4096);
  document["device_name"] = "ESP32 AMG8833 Gateway";
  document["captured_at"] = millis();
  document["rf"] = lastRfRssi;
  document["rf_rssi"] = lastRfRssi;
  document["cc1101"]["rssi"] = lastRfRssi;
  document["cc1101"]["lqi"] = lastLqi;
  document["cc1101"]["crc_ok"] = lastCrcOk;
  document["cc1101"]["received_packets"] = receivedPackets;
  document["cc1101"]["lost_packets"] = lostPackets;
  const uint32_t totalPackets = receivedPackets + lostPackets;
  document["cc1101"]["per"] = totalPackets == 0
      ? 0.0
      : static_cast<float>(lostPackets) / totalPackets;

  JsonArray pixels = document["pixels"].to<JsonArray>();
  JsonArray thermal = document["thermal"].to<JsonArray>();
  for (const float pixel : thermalPixels) {
    pixels.add(pixel);
    thermal.add(pixel);
  }

  document["ir"] = irDetected;
  document["vs1838b"]["detected"] = irDetected;
  if (!lastIrCode.isEmpty()) {
    document["vs1838b"]["code"] = lastIrCode;
  }
  if (!lastIrProtocol.isEmpty()) {
    document["vs1838b"]["protocol"] = lastIrProtocol;
  }
  document["wifi"] = 0;

  String response;
  serializeJson(document, response);
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  server.send(200, "application/json", response);
}

void handleCorsOptions() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  server.send(204);
}

void setup() {
  Serial.begin(115200);
  delay(200);

  WiFi.mode(WIFI_AP);
  if (!WiFi.softAP(AP_SSID, AP_PASSWORD)) {
    Serial.println("Wi-Fi AP start failed");
  } else {
    Serial.printf("Wi-Fi AP ready: %s, IP: %s\n",
                  AP_SSID,
                  WiFi.softAPIP().toString().c_str());
  }
  server.on("/data", HTTP_GET, handleData);
  server.on("/data", HTTP_OPTIONS, handleCorsOptions);
  server.on("/", HTTP_GET, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "text/plain", "Anti-Pinhole ESP32 gateway: GET /data");
  });
  server.begin();

  Wire.begin(I2C_SDA, I2C_SCL);
  if (!amg.begin(0x69)) {
    Serial.println("AMG8833 not found at 0x69; trying 0x68");
    thermalReady = amg.begin(0x68);
  } else {
    thermalReady = true;
  }
  if (!thermalReady) {
    Serial.println("AMG8833 unavailable; thermal values will be 0");
  }

  irrecv.enableIRIn();

  SPI.begin(CC1101_SCK, CC1101_MISO, CC1101_MOSI, CC1101_CS);
  const int16_t radioState = radio.begin(433.0, 4.8, 5.0, 125.0, 10, 16);
  if (radioState != RADIOLIB_ERR_NONE) {
    Serial.printf("CC1101 init failed: %d\n", radioState);
  } else {
    radioReady = true;
    radio.setPacketReceivedAction(onRadioPacket);
    radio.startReceive();
  }
  Serial.printf("Gateway ready: http://%s/data\n",
                WiFi.softAPIP().toString().c_str());
}

void loop() {
  readInfrared();
  readRadio();
  server.handleClient();
  delay(2);
}
