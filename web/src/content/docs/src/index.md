# Introduction

Ceratina is an open-source environmental data logger built on the ESP32-S3. It bridges the gap between embedded sensor hardware and modern web-based monitoring, providing a unified stack from bootloader to browser.

## What is Ceratina?

Ceratina is a data logging platform by [Apidae Systems](https://www.apidaesystems.ca) designed for environmental monitoring. It collects temperature, humidity, voltage, and other sensor data through an I2C mux, and serves it via a real-time web dashboard.

## Key Features

- **Multi-sensor support** via TCA9548A I2C multiplexer (up to 8 sensor channels)
- **Real-time web dashboard** with live data streaming via CloudEvents
- **Browser-based terminal** for device management over WebSocket
- **SSH access** with MicroShell virtual filesystem
- **WiFi provisioning** with captive portal and access point fallback
- **SD card and LittleFS** dual filesystem support
- **CSV export** for all sensor data directly from the browser
- **OTA-ready** firmware architecture on PlatformIO + Arduino

## Architecture

```
Browser (Dioxus WASM)
    ↕ HTTP/WebSocket
ESP32-S3 Firmware (PlatformIO C++)
    ↕ I2C / SPI / UART
Sensors & Peripherals
```

The system is split into three layers:

1. **Firmware** (`src/`) — PlatformIO C++ with Arduino framework, ESPAsyncWebServer, MicroShell, LibSSH
2. **Web App** (`web/`) — Dioxus 0.7 fullstack app compiled to WASM
3. **Hardware** — Custom carrier board with TCA9548A mux, DS3231 RTC, AT24C32 EEPROM, Neopixel status LED

## Supported Sensors

| Sensor | Type | Interface | Address |
|--------|------|-----------|---------|
| CHT832X (SEN0546) | Temperature & Humidity | I2C via mux | 0x44 |
| ADS1115 | 4-channel voltage monitor | I2C via mux | 0x48 |
| DS3231 | Real-time clock | I2C direct | 0x68 |
| AT24C32 | 4KB EEPROM | I2C direct | 0x50 |
| SCD30 / SCD4x | CO2 + T&H | I2C | 0x61 / 0x62 |
