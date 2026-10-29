# ESP32 感測器閘道接線

適用於 **ESP32-C5-DevKitC-1 v1.1**。所有模組必須共地。

| 模組 | 模組接腳 | ESP32 |
|---|---|---|
| AMG8833 | VIN / VCC | 3V3 |
| AMG8833 | GND | GND |
| AMG8833 | SDA | GPIO2 |
| AMG8833 | SCL | GPIO3 |
| VS1838B | VCC | 3V3 |
| VS1838B | GND | GND |
| VS1838B | OUT | GPIO10 |
| CC1101 | VCC | 3V3 |
| CC1101 | GND | GND |
| CC1101 | SCK | GPIO4 |
| CC1101 | MISO | GPIO5 |
| CC1101 | MOSI | GPIO6 |
| CC1101 | CSN/SS | GPIO7 |
| CC1101 | GDO0 | GPIO8 |
| CC1101 | GDO2 | GPIO9 |

CC1101 常見 8-pin 模組沒有獨立 RST 腳位，因此不需要接 GPIO11。
程式將 RadioLib 的 reset 參數設為 `-1`，使用 SPI 初始化 CC1101。

## 供電注意

- AMG8833、CC1101、VS1838B 的邏輯電壓以 **3.3 V** 為準，不要把 5 V 直接接到 ESP32 GPIO。
- CC1101 對 3.3 V 供電品質敏感，建議在模組 VCC/GND 附近加 0.1 uF 與 10 uF 去耦電容。
- 不同 CC1101 模組的接腳絲印可能是 `CSN`、`SS` 或 `CS`，它們都接 GPIO5。
- AMG8833 若模組位址是 `0x68`，請把程式中的 `amg.begin(0x69)` 改成 `amg.begin(0x68)`。

## 讓 App 取得資料

1. Arduino IDE 選擇 ESP32C5 Dev Module。
2. 安裝程式註解列出的五個函式庫。
3. 上傳 `esp32_sensor_gateway.ino`。
4. 手機連線 Wi-Fi：`AntiPinhole-ESP32`，密碼：`antipinhole`。
5. App 的熱成像頁按「連接 ESP32 Wi-Fi」；資料端點是 `http://192.168.4.1/data`。

`/data` 會同時回傳 64 個 AMG8833 溫度像素、CC1101 RSSI/LQI/PER、以及 VS1838B 的紅外線偵測狀態與解碼結果。

VS1838B 只能解碼紅外線遙控訊號；如果沒有收到完整訊號，`detected` 會是 `false`。CC1101 範例的頻率與調變參數必須和發射端一致。
