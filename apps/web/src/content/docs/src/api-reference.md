# API Reference

All endpoints are served by the device's ESPAsyncWebServer on port 80.

## Device Status

### `GET /api/status`

Basic device info (hostname, platform, uptime, heap, IP, RSSI).

### `GET /api/system/device/status`

CloudEvent-format status with nested device, network, runtime, and storage objects.

Query params: `?location=sd|littlefs`

## Sensors

### `GET /api/cloudevents`

Returns a CloudEvents batch (`application/cloudevents-batch+json`) with all sensor readings:

- `status.v1` — heap, chip, IP, uptime
- `sensors.temperature_and_humidity.v1` — CHT832X readings per mux channel
- `sensors.power.v1` — ADS1115 voltage channels + gain

### `GET /api/co2/config`

CO2 sensor configuration (model, interval, calibration, offset, altitude).

### `POST /api/co2/config`

Set CO2 config. Body: `{"measurement_interval_seconds": 5, "auto_calibration_enabled": true, ...}`

### `POST /api/co2/start` / `POST /api/co2/stop`

Start or stop CO2 measurement.

## WiFi

### `GET /api/wireless/status`

Connection state, STA SSID/IP/RSSI, AP state/SSID/IP.

### `POST /api/wireless/actions/scan`

Scan for nearby WiFi networks. Returns SSID, RSSI, channel, encryption for each.

### `POST /api/wireless/actions/connect`

Connect to a network. Body: `{"ssid": "...", "password": "..."}`

## Access Point

### `GET /api/ap/config`

AP configuration (SSID, password, enabled state, active state, IP).

### `POST /api/ap/config`

Set AP config. Body: `{"ssid": "...", "password": "...", "enabled": true}`

## Filesystem

### `GET /api/filesystem/list`

List files. Query params: `?location=sd|littlefs`

### `DELETE /api/filesystem/delete`

Delete a file. Query params: `?location=sd|littlefs&path=/filename`

### `POST /api/upload`

Upload file to SD card (multipart form data).

### `GET /api/files`

List SD card root directory.

## WebSocket

### `ws://device/ws/shell`

Interactive MicroShell session. Send text frames (keystrokes), receive text frames (terminal output with ANSI escape codes). Limited to 1 concurrent client.
