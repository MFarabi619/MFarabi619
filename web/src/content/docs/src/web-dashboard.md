# Web Dashboard

The web dashboard is a Dioxus 0.7 fullstack app compiled to WASM. It runs in the browser and communicates with the device over HTTP and WebSocket.

## Panels

### Measurements

Tabbed interface with three sensor views:

- **Temp/Humidity** — CHT832X readings from mux channels, with per-sensor columns
- **Voltage** — ADS1115 4-channel readings with gain display
- **CO2** — SCD30/SCD4x PPM, temperature, humidity with inline config controls

Each tab has CSV export and a Sample button (Ctrl+Enter shortcut).

### Terminal

Browser-based shell powered by xterm.js over WebSocket (`/ws/shell`). Provides the same MicroShell experience as SSH — browse the virtual filesystem, read sensors, manage WiFi, reboot the device.

### Network

WiFi scan, connect, and AP configuration. Shows connected SSID, RSSI, and IP in the status bar.

### Filesystem

Browse and manage files on SD card and LittleFS. Delete files, download from SD, and view storage usage with progress bars.

## Polling

The dashboard polls the device every 5 seconds via `/api/cloudevents`. Sensor readings are deduplicated by event timestamp and value comparison to avoid redundant rows. The polling coroutine skips cycles when a manual sample is in progress.

## Device URL

The device URL defaults to `http://ceratina.local` (mDNS). It can be changed in the URL bar and persists in localStorage. The status badge shows the device IP when connected, with SSID and RSSI on hover.
