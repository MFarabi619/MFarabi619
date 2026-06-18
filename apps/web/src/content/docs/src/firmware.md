# Firmware

## Project Structure

```
src/
  config.h              Central CONFIG_ constants
  main.cpp              Boot orchestration, service loop
  console/
    icons.h             Nerd Font glyph constants
    colors.h            ANSI escape + RGB color constants
  drivers/
    ads1115.cpp         ADS1115 voltage monitor (auto-discovers mux channel)
    ds3231.cpp          DS3231 RTC
    neopixel.cpp        Adafruit NeoPixel wrapper
    tca9548a.cpp        TCA9548A I2C mux
  networking/
    wifi.cpp            STA + AP mode, DNS captive portal, NVS credentials
    sntp.cpp            NTP time sync with DS3231 update
  programs/
    shell/
      shell.cpp         MicroShell init, hostname management
      commands.cpp      reboot, reset, exit, wifi-set, wifi-connect
      fs/               Virtual filesystem mounts (/dev, /etc, /bin, etc.)
    ssh/
      ssh_server.cpp    LibSSH callback-based SSH server
      ssh_client.cpp    ssh-exec, scp-get, scp-put, ota commands
  services/
    http.cpp            ESPAsyncWebServer, all API routes, captive portal
    cloudevents.cpp     CloudEvents batch endpoint
    ws_shell.cpp        WebSocket-to-MicroShell bridge
    temperature_and_humidity.cpp  CHT832X sensor service
    eeprom.cpp          AT24C32 EEPROM driver
  testing/
    it.h                Screenplay test pattern macro
```

## Configuration

All constants are in `src/config.h` with `CONFIG_` prefix and `#ifndef` guards for build-flag override. Key sections:

- Deployment (hostname, platform)
- Neopixel (GPIO, brightness)
- SSH (port, hostkey paths, buffer sizes)
- WiFi (timeout, NVS namespace, AP credentials)
- I2C (bus GPIOs, frequency, mux address)
- Sensors (T&H address, voltage monitor channels)
- CloudEvents (tenant, site)

## Testing

Tests use the Unity framework with a screenplay pattern (`it()` macro). The custom test runner (`tests/test_custom_runner.py`) auto-discovers `*_run_tests()` functions in `src/` and generates `tests/test_unit/main.cpp`.

```bash
pio test              # Run all tests
pio test -v           # Verbose output
```

Tests save and restore NVS state so WiFi credentials persist across test runs.
