# Getting Started

## Prerequisites

- [PlatformIO](https://platformio.org/) CLI or IDE extension
- ESP32-S3 development board with the Ceratina carrier board
- USB-C cable for flashing

## Flashing the Firmware

Set your WiFi credentials as environment variables:

```bash
export WIFI_SSID=your_network
export WIFI_PASSWORD=your_password
```

Build and flash:

```bash
pio run --target upload
```

The device will:
1. Power on the I2C sensor relay
2. Initialize the TCA9548A mux and discover sensors
3. Start the access point (`ceratina-access-point`)
4. Attempt to connect to your WiFi network
5. Start the HTTP server, SSH server, and WebSocket shell

## Connecting

Once connected to WiFi, the device is reachable at:

- **Web dashboard**: `http://ceratina.local`
- **SSH**: `ssh $USER@ceratina.local`
- **WebSocket shell**: `ws://ceratina.local/ws/shell`

If WiFi is not configured, connect to the `ceratina-access-point` WiFi network (password: `apidaesystems`) and navigate to `http://192.168.4.1`.

## Running Tests

```bash
pio test
```

Tests run on-device via UART. The custom test runner auto-discovers all `*_run_tests()` functions and generates a Unity test harness.
