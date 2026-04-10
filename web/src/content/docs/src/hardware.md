# Hardware

## Ceratina Carrier Board

The carrier board connects an ESP32-S3 to external sensors via a TCA9548A I2C multiplexer. Each of the 8 mux channels is routed to a D-SUB 9-pin connector for plug-and-play sensor modules.

## I2C Bus Layout

| Bus | Devices | Notes |
|-----|---------|-------|
| Wire0 (GPIO 15/16) | DS3231 RTC | Always-on, coin cell backed |
| Wire1 (GPIO 17/18) | TCA9548A mux (0x70), AT24C32 EEPROM (0x50) | Direct on bus |
| Wire1 via mux ch0-7 | CHT832X, ADS1115, etc. | Behind relay power |

## GPIO Assignments

| GPIO | Function |
|------|----------|
| 5 | I2C sensor relay power |
| 10 | SD card chip select (SPI) |
| 15 | I2C Bus 0 SDA |
| 16 | I2C Bus 0 SCL |
| 17 | I2C Bus 1 SDA |
| 18 | I2C Bus 1 SCL |
| 38 | Neopixel data |

## Neopixel Status LED

| Color | Meaning |
|-------|---------|
| Blue | Booting |
| Red | LittleFS formatting |
| Green | WiFi connected |
| Yellow | WiFi disconnected / AP only |
| White | SSH client connected |
| Magenta | Custom (via `/dev/led`) |
