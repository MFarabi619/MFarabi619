#[derive(
    Clone,
    Copy,
    dioxus_router::Routable,
    PartialEq,
    Eq,
    Hash,
    Debug,
    serde::Serialize,
    serde::Deserialize
)]
pub enum BookRoute {
    #[route("/#:section")]
    Index { section: IndexSection },
    #[route("/getting-started#:section")]
    GettingStarted { section: GettingStartedSection },
    #[route("/hardware#:section")]
    Hardware { section: HardwareSection },
    #[route("/firmware#:section")]
    Firmware { section: FirmwareSection },
    #[route("/web-dashboard#:section")]
    WebDashboard { section: WebDashboardSection },
    #[route("/shell-commands#:section")]
    ShellCommands { section: ShellCommandsSection },
    #[route("/api-reference#:section")]
    ApiReference { section: ApiReferenceSection },
}
impl BookRoute {
    /// Get the markdown for a page by its ID
    pub const fn page_markdown(id: use_mdbook::mdbook_shared::PageId) -> &'static str {
        match id.0 {
            3usize => {
                "# Firmware\n\n## Project Structure\n\n````\nsrc/\n  config.h              Central CONFIG_ constants\n  main.cpp              Boot orchestration, service loop\n  console/\n    icons.h             Nerd Font glyph constants\n    colors.h            ANSI escape + RGB color constants\n  drivers/\n    ads1115.cpp         ADS1115 voltage monitor (auto-discovers mux channel)\n    ds3231.cpp          DS3231 RTC\n    neopixel.cpp        Adafruit NeoPixel wrapper\n    tca9548a.cpp        TCA9548A I2C mux\n  networking/\n    wifi.cpp            STA + AP mode, DNS captive portal, NVS credentials\n    sntp.cpp            NTP time sync with DS3231 update\n  programs/\n    shell/\n      shell.cpp         MicroShell init, hostname management\n      commands.cpp      reboot, reset, exit, wifi-set, wifi-connect\n      fs/               Virtual filesystem mounts (/dev, /etc, /bin, etc.)\n    ssh/\n      ssh_server.cpp    LibSSH callback-based SSH server\n      ssh_client.cpp    ssh-exec, scp-get, scp-put, ota commands\n  services/\n    http.cpp            ESPAsyncWebServer, all API routes, captive portal\n    cloudevents.cpp     CloudEvents batch endpoint\n    ws_shell.cpp        WebSocket-to-MicroShell bridge\n    temperature_and_humidity.cpp  CHT832X sensor service\n    eeprom.cpp          AT24C32 EEPROM driver\n  testing/\n    it.h                Screenplay test pattern macro\n````\n\n## Configuration\n\nAll constants are in `src/config.h` with `CONFIG_` prefix and `#ifndef` guards for build-flag override. Key sections:\n\n* Deployment (hostname, platform)\n* Neopixel (GPIO, brightness)\n* SSH (port, hostkey paths, buffer sizes)\n* WiFi (timeout, NVS namespace, AP credentials)\n* I2C (bus GPIOs, frequency, mux address)\n* Sensors (T&H address, voltage monitor channels)\n* CloudEvents (tenant, site)\n\n## Testing\n\nTests use the Unity framework with a screenplay pattern (`it()` macro). The custom test runner (`tests/test_custom_runner.py`) auto-discovers `*_run_tests()` functions in `src/` and generates `tests/test_unit/main.cpp`.\n\n````bash\npio test              # Run all tests\npio test -v           # Verbose output\n````\n\nTests save and restore NVS state so WiFi credentials persist across test runs."
            }
            0usize => {
                "# Introduction\n\nCeratina is an open-source environmental data logger built on the ESP32-S3. It bridges the gap between embedded sensor hardware and modern web-based monitoring, providing a unified stack from bootloader to browser.\n\n## What is Ceratina?\n\nCeratina is a data logging platform by [Apidae Systems](https://www.apidaesystems.ca) designed for environmental monitoring. It collects temperature, humidity, voltage, and other sensor data through an I2C mux, and serves it via a real-time web dashboard.\n\n## Key Features\n\n* **Multi-sensor support** via TCA9548A I2C multiplexer (up to 8 sensor channels)\n* **Real-time web dashboard** with live data streaming via CloudEvents\n* **Browser-based terminal** for device management over WebSocket\n* **SSH access** with MicroShell virtual filesystem\n* **WiFi provisioning** with captive portal and access point fallback\n* **SD card and LittleFS** dual filesystem support\n* **CSV export** for all sensor data directly from the browser\n* **OTA-ready** firmware architecture on PlatformIO + Arduino\n\n## Architecture\n\n````\nBrowser (Dioxus WASM)\n    ↕ HTTP/WebSocket\nESP32-S3 Firmware (PlatformIO C++)\n    ↕ I2C / SPI / UART\nSensors & Peripherals\n````\n\nThe system is split into three layers:\n\n1. **Firmware** (`src/`) — PlatformIO C++ with Arduino framework, ESPAsyncWebServer, MicroShell, LibSSH\n1. **Web App** (`web/`) — Dioxus 0.7 fullstack app compiled to WASM\n1. **Hardware** — Custom carrier board with TCA9548A mux, DS3231 RTC, AT24C32 EEPROM, Neopixel status LED\n\n## Supported Sensors\n\n|Sensor|Type|Interface|Address|\n|------|----|---------|-------|\n|CHT832X (SEN0546)|Temperature & Humidity|I2C via mux|0x44|\n|ADS1115|4-channel voltage monitor|I2C via mux|0x48|\n|DS3231|Real-time clock|I2C direct|0x68|\n|AT24C32|4KB EEPROM|I2C direct|0x50|\n|SCD30 / SCD4x|CO2 + T&H|I2C|0x61 / 0x62|"
            }
            5usize => {
                "# Shell Commands\n\nThe MicroShell virtual filesystem is accessible via SSH or the browser terminal.\n\n## Commands\n\n|Command|Description|\n|-------|-----------|\n|`help`|List all commands|\n|`ls`|List directory contents|\n|`cd <path>`|Change directory|\n|`cat <file>`|Read file contents|\n|`echo <text> > <file>`|Write to file|\n|`reboot`|Reboot the device|\n|`reset`|Reset shell state|\n|`exit`|Close SSH session|\n|`wifi-set <ssid> <password>`|Save WiFi credentials to NVS|\n|`wifi-connect`|Connect to saved WiFi network|\n|`ssh-exec <host> <user> <pass> <cmd>`|Execute command on remote host|\n|`scp-get <host> <user> <pass> <remote> <local>`|Download file from remote host|\n|`scp-put <host> <user> <pass> <local> <remote>`|Upload file to remote host|\n|`ota <host> <user> <pass> <firmware-path>`|OTA firmware update via SCP|\n\n## Virtual Filesystem\n\n````\n/\n  bin/                  Commands (reboot, wifi-set, etc.)\n  dev/\n    null                Discard sink\n    random              Hardware RNG (esp_random)\n    uptime              System uptime\n    heap                Heap memory usage\n    time                Local time (NTP-synced)\n    led                 Neopixel control (write: off/red/green/blue/yellow/magenta/cyan/white)\n    bus/\n      i2c0              I2C bus 0 scan\n      i2c1              I2C bus 1 scan\n      mux               TCA9548A mux scan (all channels)\n    sensors/\n      i2c_scan          Full I2C device scan\n      rtc               DS3231 time + oscillator status\n      temperature       DS3231 temperature\n    sd/\n      info              SD card mount info\n    ssh/\n      fingerprint       SSH host key fingerprint\n    mem/                Memory info\n  etc/\n    hostname            Read/write hostname\n    config              CPU, flash, SDK info\n    wifi                Read/write WiFi credentials (ssid:password)\n    user                Current SSH user\n````\n\n## Examples\n\n````bash\ncat /dev/heap           # Show heap memory\ncat /dev/time           # Show current time\necho red > /dev/led     # Set neopixel to red\ncat /dev/bus/mux        # Scan all mux channels\ncat /etc/hostname       # Read hostname\necho ceratina > /etc/hostname  # Set hostname\n````"
            }
            1usize => {
                "# Getting Started\n\n## Prerequisites\n\n* [PlatformIO](https://platformio.org/) CLI or IDE extension\n* ESP32-S3 development board with the Ceratina carrier board\n* USB-C cable for flashing\n\n## Flashing the Firmware\n\nSet your WiFi credentials as environment variables:\n\n````bash\nexport WIFI_SSID=your_network\nexport WIFI_PASSWORD=your_password\n````\n\nBuild and flash:\n\n````bash\npio run --target upload\n````\n\nThe device will:\n\n1. Power on the I2C sensor relay\n1. Initialize the TCA9548A mux and discover sensors\n1. Start the access point (`ceratina-access-point`)\n1. Attempt to connect to your WiFi network\n1. Start the HTTP server, SSH server, and WebSocket shell\n\n## Connecting\n\nOnce connected to WiFi, the device is reachable at:\n\n* **Web dashboard**: `http://ceratina.local`\n* **SSH**: `ssh $USER@ceratina.local`\n* **WebSocket shell**: `ws://ceratina.local/ws/shell`\n\nIf WiFi is not configured, connect to the `ceratina-access-point` WiFi network (password: `apidaesystems`) and navigate to `http://192.168.4.1`.\n\n## Running Tests\n\n````bash\npio test\n````\n\nTests run on-device via UART. The custom test runner auto-discovers all `*_run_tests()` functions and generates a Unity test harness."
            }
            2usize => {
                "# Hardware\n\n## Ceratina Carrier Board\n\nThe carrier board connects an ESP32-S3 to external sensors via a TCA9548A I2C multiplexer. Each of the 8 mux channels is routed to a D-SUB 9-pin connector for plug-and-play sensor modules.\n\n## I2C Bus Layout\n\n|Bus|Devices|Notes|\n|---|-------|-----|\n|Wire0 (GPIO 15/16)|DS3231 RTC|Always-on, coin cell backed|\n|Wire1 (GPIO 17/18)|TCA9548A mux (0x70), AT24C32 EEPROM (0x50)|Direct on bus|\n|Wire1 via mux ch0-7|CHT832X, ADS1115, etc.|Behind relay power|\n\n## GPIO Assignments\n\n|GPIO|Function|\n|----|--------|\n|5|I2C sensor relay power|\n|10|SD card chip select (SPI)|\n|15|I2C Bus 0 SDA|\n|16|I2C Bus 0 SCL|\n|17|I2C Bus 1 SDA|\n|18|I2C Bus 1 SCL|\n|38|Neopixel data|\n\n## Neopixel Status LED\n\n|Color|Meaning|\n|-----|-------|\n|Blue|Booting|\n|Red|LittleFS formatting|\n|Green|WiFi connected|\n|Yellow|WiFi disconnected / AP only|\n|White|SSH client connected|\n|Magenta|Custom (via `/dev/led`)|"
            }
            4usize => {
                "# Web Dashboard\n\nThe web dashboard is a Dioxus 0.7 fullstack app compiled to WASM. It runs in the browser and communicates with the device over HTTP and WebSocket.\n\n## Panels\n\n### Measurements\n\nTabbed interface with three sensor views:\n\n* **Temp/Humidity** — CHT832X readings from mux channels, with per-sensor columns\n* **Voltage** — ADS1115 4-channel readings with gain display\n* **CO2** — SCD30/SCD4x PPM, temperature, humidity with inline config controls\n\nEach tab has CSV export and a Sample button (Ctrl+Enter shortcut).\n\n### Terminal\n\nBrowser-based shell powered by xterm.js over WebSocket (`/ws/shell`). Provides the same MicroShell experience as SSH — browse the virtual filesystem, read sensors, manage WiFi, reboot the device.\n\n### Network\n\nWiFi scan, connect, and AP configuration. Shows connected SSID, RSSI, and IP in the status bar.\n\n### Filesystem\n\nBrowse and manage files on SD card and LittleFS. Delete files, download from SD, and view storage usage with progress bars.\n\n## Polling\n\nThe dashboard polls the device every 5 seconds via `/api/cloudevents`. Sensor readings are deduplicated by event timestamp and value comparison to avoid redundant rows. The polling coroutine skips cycles when a manual sample is in progress.\n\n## Device URL\n\nThe device URL defaults to `http://ceratina.local` (mDNS). It can be changed in the URL bar and persists in localStorage. The status badge shows the device IP when connected, with SSID and RSSI on hover."
            }
            6usize => {
                "# API Reference\n\nAll endpoints are served by the device's ESPAsyncWebServer on port 80.\n\n## Device Status\n\n### `GET /api/status`\n\nBasic device info (hostname, platform, uptime, heap, IP, RSSI).\n\n### `GET /api/system/device/status`\n\nCloudEvent-format status with nested device, network, runtime, and storage objects.\n\nQuery params: `?location=sd|littlefs`\n\n## Sensors\n\n### `GET /api/cloudevents`\n\nReturns a CloudEvents batch (`application/cloudevents-batch+json`) with all sensor readings:\n\n* `status.v1` — heap, chip, IP, uptime\n* `sensors.temperature_and_humidity.v1` — CHT832X readings per mux channel\n* `sensors.power.v1` — ADS1115 voltage channels + gain\n\n### `GET /api/co2/config`\n\nCO2 sensor configuration (model, interval, calibration, offset, altitude).\n\n### `POST /api/co2/config`\n\nSet CO2 config. Body: `{\"measurement_interval_seconds\": 5, \"auto_calibration_enabled\": true, ...}`\n\n### `POST /api/co2/start` / `POST /api/co2/stop`\n\nStart or stop CO2 measurement.\n\n## WiFi\n\n### `GET /api/wireless/status`\n\nConnection state, STA SSID/IP/RSSI, AP state/SSID/IP.\n\n### `POST /api/wireless/actions/scan`\n\nScan for nearby WiFi networks. Returns SSID, RSSI, channel, encryption for each.\n\n### `POST /api/wireless/actions/connect`\n\nConnect to a network. Body: `{\"ssid\": \"...\", \"password\": \"...\"}`\n\n## Access Point\n\n### `GET /api/ap/config`\n\nAP configuration (SSID, password, enabled state, active state, IP).\n\n### `POST /api/ap/config`\n\nSet AP config. Body: `{\"ssid\": \"...\", \"password\": \"...\", \"enabled\": true}`\n\n## Filesystem\n\n### `GET /api/filesystem/list`\n\nList files. Query params: `?location=sd|littlefs`\n\n### `DELETE /api/filesystem/delete`\n\nDelete a file. Query params: `?location=sd|littlefs&path=/filename`\n\n### `POST /api/upload`\n\nUpload file to SD card (multipart form data).\n\n### `GET /api/files`\n\nList SD card root directory.\n\n## WebSocket\n\n### `ws://device/ws/shell`\n\nInteractive MicroShell session. Send text frames (keystrokes), receive text frames (terminal output with ANSI escape codes). Limited to 1 concurrent client."
            }
            _ => panic!("Invalid page ID:"),
        }
    }
    pub fn sections(&self) -> &'static [use_mdbook::mdbook_shared::Section] {
        &self.page().sections
    }
    pub fn page(&self) -> &'static use_mdbook::mdbook_shared::Page<Self> {
        LAZY_BOOK.get_page(self)
    }
    pub fn page_id(&self) -> use_mdbook::mdbook_shared::PageId {
        match self {
            BookRoute::Index { .. } => use_mdbook::mdbook_shared::PageId(0usize),
            BookRoute::GettingStarted { .. } => use_mdbook::mdbook_shared::PageId(1usize),
            BookRoute::Hardware { .. } => use_mdbook::mdbook_shared::PageId(2usize),
            BookRoute::Firmware { .. } => use_mdbook::mdbook_shared::PageId(3usize),
            BookRoute::WebDashboard { .. } => use_mdbook::mdbook_shared::PageId(4usize),
            BookRoute::ShellCommands { .. } => use_mdbook::mdbook_shared::PageId(5usize),
            BookRoute::ApiReference { .. } => use_mdbook::mdbook_shared::PageId(6usize),
        }
    }
}
impl Default for BookRoute {
    fn default() -> Self {
        BookRoute::Index {
            section: IndexSection::Empty,
        }
    }
}
pub static LAZY_BOOK: use_mdbook::Lazy<use_mdbook::mdbook_shared::MdBook<BookRoute>> = use_mdbook::Lazy::new(||
{
    {
        let mut page_id_mapping = ::std::collections::HashMap::new();
        let mut pages = Vec::new();
        let __push_page_0: fn(_, _) = |
            _pages: &mut Vec<_>,
            _page_id_mapping: &mut std::collections::HashMap<_, _>|
        {
            _pages
                .push((
                    0usize,
                    {
                        ::use_mdbook::mdbook_shared::Page {
                            title: "Introduction".to_string(),
                            url: BookRoute::Index {
                                section: IndexSection::Empty,
                            },
                            segments: vec![],
                            sections: vec![
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Introduction".to_string(),
                                    id: "introduction".to_string(),
                                    level: 1usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "What is Ceratina?".to_string(),
                                    id: "what-is-ceratina".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Key Features".to_string(),
                                    id: "key-features".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Architecture".to_string(),
                                    id: "architecture".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Supported Sensors".to_string(),
                                    id: "supported-sensors".to_string(),
                                    level: 2usize,
                                },
                            ],
                            raw: String::new(),
                            id: ::use_mdbook::mdbook_shared::PageId(0usize),
                        }
                    },
                ));
            _page_id_mapping
                .insert(
                    BookRoute::Index {
                        section: IndexSection::Empty,
                    },
                    ::use_mdbook::mdbook_shared::PageId(0usize),
                );
        };
        __push_page_0(&mut pages, &mut page_id_mapping);
        let __push_page_1: fn(_, _) = |
            _pages: &mut Vec<_>,
            _page_id_mapping: &mut std::collections::HashMap<_, _>|
        {
            _pages
                .push((
                    1usize,
                    {
                        ::use_mdbook::mdbook_shared::Page {
                            title: "Getting Started".to_string(),
                            url: BookRoute::GettingStarted {
                                section: GettingStartedSection::Empty,
                            },
                            segments: vec![],
                            sections: vec![
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Getting Started".to_string(),
                                    id: "getting-started".to_string(),
                                    level: 1usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Prerequisites".to_string(),
                                    id: "prerequisites".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Flashing the Firmware".to_string(),
                                    id: "flashing-the-firmware".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Connecting".to_string(),
                                    id: "connecting".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Running Tests".to_string(),
                                    id: "running-tests".to_string(),
                                    level: 2usize,
                                },
                            ],
                            raw: String::new(),
                            id: ::use_mdbook::mdbook_shared::PageId(1usize),
                        }
                    },
                ));
            _page_id_mapping
                .insert(
                    BookRoute::GettingStarted {
                        section: GettingStartedSection::Empty,
                    },
                    ::use_mdbook::mdbook_shared::PageId(1usize),
                );
        };
        __push_page_1(&mut pages, &mut page_id_mapping);
        let __push_page_2: fn(_, _) = |
            _pages: &mut Vec<_>,
            _page_id_mapping: &mut std::collections::HashMap<_, _>|
        {
            _pages
                .push((
                    2usize,
                    {
                        ::use_mdbook::mdbook_shared::Page {
                            title: "Hardware".to_string(),
                            url: BookRoute::Hardware {
                                section: HardwareSection::Empty,
                            },
                            segments: vec![],
                            sections: vec![
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Hardware".to_string(),
                                    id: "hardware".to_string(),
                                    level: 1usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Ceratina Carrier Board".to_string(),
                                    id: "ceratina-carrier-board".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "I2C Bus Layout".to_string(),
                                    id: "i2c-bus-layout".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "GPIO Assignments".to_string(),
                                    id: "gpio-assignments".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Neopixel Status LED".to_string(),
                                    id: "neopixel-status-led".to_string(),
                                    level: 2usize,
                                },
                            ],
                            raw: String::new(),
                            id: ::use_mdbook::mdbook_shared::PageId(2usize),
                        }
                    },
                ));
            _page_id_mapping
                .insert(
                    BookRoute::Hardware {
                        section: HardwareSection::Empty,
                    },
                    ::use_mdbook::mdbook_shared::PageId(2usize),
                );
        };
        __push_page_2(&mut pages, &mut page_id_mapping);
        let __push_page_3: fn(_, _) = |
            _pages: &mut Vec<_>,
            _page_id_mapping: &mut std::collections::HashMap<_, _>|
        {
            _pages
                .push((
                    3usize,
                    {
                        ::use_mdbook::mdbook_shared::Page {
                            title: "Firmware".to_string(),
                            url: BookRoute::Firmware {
                                section: FirmwareSection::Empty,
                            },
                            segments: vec![],
                            sections: vec![
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Firmware".to_string(),
                                    id: "firmware".to_string(),
                                    level: 1usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Project Structure".to_string(),
                                    id: "project-structure".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Configuration".to_string(),
                                    id: "configuration".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Testing".to_string(),
                                    id: "testing".to_string(),
                                    level: 2usize,
                                },
                            ],
                            raw: String::new(),
                            id: ::use_mdbook::mdbook_shared::PageId(3usize),
                        }
                    },
                ));
            _page_id_mapping
                .insert(
                    BookRoute::Firmware {
                        section: FirmwareSection::Empty,
                    },
                    ::use_mdbook::mdbook_shared::PageId(3usize),
                );
        };
        __push_page_3(&mut pages, &mut page_id_mapping);
        let __push_page_4: fn(_, _) = |
            _pages: &mut Vec<_>,
            _page_id_mapping: &mut std::collections::HashMap<_, _>|
        {
            _pages
                .push((
                    4usize,
                    {
                        ::use_mdbook::mdbook_shared::Page {
                            title: "Web Dashboard".to_string(),
                            url: BookRoute::WebDashboard {
                                section: WebDashboardSection::Empty,
                            },
                            segments: vec![],
                            sections: vec![
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Web Dashboard".to_string(),
                                    id: "web-dashboard".to_string(),
                                    level: 1usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Panels".to_string(),
                                    id: "panels".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Measurements".to_string(),
                                    id: "measurements".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Terminal".to_string(),
                                    id: "terminal".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Network".to_string(),
                                    id: "network".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Filesystem".to_string(),
                                    id: "filesystem".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Polling".to_string(),
                                    id: "polling".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Device URL".to_string(),
                                    id: "device-url".to_string(),
                                    level: 2usize,
                                },
                            ],
                            raw: String::new(),
                            id: ::use_mdbook::mdbook_shared::PageId(4usize),
                        }
                    },
                ));
            _page_id_mapping
                .insert(
                    BookRoute::WebDashboard {
                        section: WebDashboardSection::Empty,
                    },
                    ::use_mdbook::mdbook_shared::PageId(4usize),
                );
        };
        __push_page_4(&mut pages, &mut page_id_mapping);
        let __push_page_5: fn(_, _) = |
            _pages: &mut Vec<_>,
            _page_id_mapping: &mut std::collections::HashMap<_, _>|
        {
            _pages
                .push((
                    5usize,
                    {
                        ::use_mdbook::mdbook_shared::Page {
                            title: "Shell Commands".to_string(),
                            url: BookRoute::ShellCommands {
                                section: ShellCommandsSection::Empty,
                            },
                            segments: vec![],
                            sections: vec![
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Shell Commands".to_string(),
                                    id: "shell-commands".to_string(),
                                    level: 1usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Commands".to_string(),
                                    id: "commands".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Virtual Filesystem".to_string(),
                                    id: "virtual-filesystem".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Examples".to_string(),
                                    id: "examples".to_string(),
                                    level: 2usize,
                                },
                            ],
                            raw: String::new(),
                            id: ::use_mdbook::mdbook_shared::PageId(5usize),
                        }
                    },
                ));
            _page_id_mapping
                .insert(
                    BookRoute::ShellCommands {
                        section: ShellCommandsSection::Empty,
                    },
                    ::use_mdbook::mdbook_shared::PageId(5usize),
                );
        };
        __push_page_5(&mut pages, &mut page_id_mapping);
        let __push_page_6: fn(_, _) = |
            _pages: &mut Vec<_>,
            _page_id_mapping: &mut std::collections::HashMap<_, _>|
        {
            _pages
                .push((
                    6usize,
                    {
                        ::use_mdbook::mdbook_shared::Page {
                            title: "API Reference".to_string(),
                            url: BookRoute::ApiReference {
                                section: ApiReferenceSection::Empty,
                            },
                            segments: vec![],
                            sections: vec![
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "API Reference".to_string(),
                                    id: "api-reference".to_string(),
                                    level: 1usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Device Status".to_string(),
                                    id: "device-status".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "GET /api/status".to_string(),
                                    id: "get-apistatus".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "GET /api/system/device/status".to_string(),
                                    id: "get-apisystemdevicestatus".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Sensors".to_string(),
                                    id: "sensors".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "GET /api/cloudevents".to_string(),
                                    id: "get-apicloudevents".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "GET /api/co2/config".to_string(),
                                    id: "get-apico2config".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "POST /api/co2/config".to_string(),
                                    id: "post-apico2config".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "POST /api/co2/start / POST /api/co2/stop"
                                        .to_string(),
                                    id: "post-apico2start--post-apico2stop".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "WiFi".to_string(),
                                    id: "wifi".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "GET /api/wireless/status".to_string(),
                                    id: "get-apiwirelessstatus".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "POST /api/wireless/actions/scan".to_string(),
                                    id: "post-apiwirelessactionsscan".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "POST /api/wireless/actions/connect".to_string(),
                                    id: "post-apiwirelessactionsconnect".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Access Point".to_string(),
                                    id: "access-point".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "GET /api/ap/config".to_string(),
                                    id: "get-apiapconfig".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "POST /api/ap/config".to_string(),
                                    id: "post-apiapconfig".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "Filesystem".to_string(),
                                    id: "filesystem".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "GET /api/filesystem/list".to_string(),
                                    id: "get-apifilesystemlist".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "DELETE /api/filesystem/delete".to_string(),
                                    id: "delete-apifilesystemdelete".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "POST /api/upload".to_string(),
                                    id: "post-apiupload".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "GET /api/files".to_string(),
                                    id: "get-apifiles".to_string(),
                                    level: 3usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "WebSocket".to_string(),
                                    id: "websocket".to_string(),
                                    level: 2usize,
                                },
                                ::use_mdbook::mdbook_shared::Section {
                                    title: "ws://device/ws/shell".to_string(),
                                    id: "wsdevicewsshell".to_string(),
                                    level: 3usize,
                                },
                            ],
                            raw: String::new(),
                            id: ::use_mdbook::mdbook_shared::PageId(6usize),
                        }
                    },
                ));
            _page_id_mapping
                .insert(
                    BookRoute::ApiReference {
                        section: ApiReferenceSection::Empty,
                    },
                    ::use_mdbook::mdbook_shared::PageId(6usize),
                );
        };
        __push_page_6(&mut pages, &mut page_id_mapping);
        ::use_mdbook::mdbook_shared::MdBook {
            summary: ::use_mdbook::mdbook_shared::Summary {
                title: Some("Summary".to_string()),
                prefix_chapters: vec![],
                numbered_chapters: vec![
                    ::use_mdbook::mdbook_shared::SummaryItem::Link(::use_mdbook::mdbook_shared::Link {
                        name: "Introduction".to_string(),
                        location: Some(BookRoute::Index {
                            section: IndexSection::Empty,
                        }),
                        number: Some(
                            ::use_mdbook::mdbook_shared::SectionNumber(vec![1u32]),
                        ),
                        nested_items: vec![],
                    }),
                    ::use_mdbook::mdbook_shared::SummaryItem::Link(::use_mdbook::mdbook_shared::Link {
                        name: "Getting Started".to_string(),
                        location: Some(BookRoute::GettingStarted {
                            section: GettingStartedSection::Empty,
                        }),
                        number: Some(
                            ::use_mdbook::mdbook_shared::SectionNumber(vec![2u32]),
                        ),
                        nested_items: vec![],
                    }),
                    ::use_mdbook::mdbook_shared::SummaryItem::Link(::use_mdbook::mdbook_shared::Link {
                        name: "Hardware".to_string(),
                        location: Some(BookRoute::Hardware {
                            section: HardwareSection::Empty,
                        }),
                        number: Some(
                            ::use_mdbook::mdbook_shared::SectionNumber(vec![3u32]),
                        ),
                        nested_items: vec![],
                    }),
                    ::use_mdbook::mdbook_shared::SummaryItem::Link(::use_mdbook::mdbook_shared::Link {
                        name: "Firmware".to_string(),
                        location: Some(BookRoute::Firmware {
                            section: FirmwareSection::Empty,
                        }),
                        number: Some(
                            ::use_mdbook::mdbook_shared::SectionNumber(vec![4u32]),
                        ),
                        nested_items: vec![],
                    }),
                    ::use_mdbook::mdbook_shared::SummaryItem::Link(::use_mdbook::mdbook_shared::Link {
                        name: "Web Dashboard".to_string(),
                        location: Some(BookRoute::WebDashboard {
                            section: WebDashboardSection::Empty,
                        }),
                        number: Some(
                            ::use_mdbook::mdbook_shared::SectionNumber(vec![5u32]),
                        ),
                        nested_items: vec![],
                    }),
                    ::use_mdbook::mdbook_shared::SummaryItem::Link(::use_mdbook::mdbook_shared::Link {
                        name: "Shell Commands".to_string(),
                        location: Some(BookRoute::ShellCommands {
                            section: ShellCommandsSection::Empty,
                        }),
                        number: Some(
                            ::use_mdbook::mdbook_shared::SectionNumber(vec![6u32]),
                        ),
                        nested_items: vec![],
                    }),
                    ::use_mdbook::mdbook_shared::SummaryItem::Link(::use_mdbook::mdbook_shared::Link {
                        name: "API Reference".to_string(),
                        location: Some(BookRoute::ApiReference {
                            section: ApiReferenceSection::Empty,
                        }),
                        number: Some(
                            ::use_mdbook::mdbook_shared::SectionNumber(vec![7u32]),
                        ),
                        nested_items: vec![],
                    }),
                ],
                suffix_chapters: vec![],
            },
            pages: pages.into_iter().collect(),
            page_id_mapping,
        }
    }
});
#[derive(
    Clone,
    Copy,
    PartialEq,
    Eq,
    Hash,
    Debug,
    Default,
    serde::Serialize,
    serde::Deserialize
)]
pub enum IndexSection {
    #[default]
    Empty,
    Introduction,
    WhatIsCeratina,
    KeyFeatures,
    Architecture,
    SupportedSensors,
}
impl std::str::FromStr for IndexSection {
    type Err = &'static str;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "" => Ok(Self::Empty),
            "introduction" => Ok(Self::Introduction),
            "what-is-ceratina" => Ok(Self::WhatIsCeratina),
            "key-features" => Ok(Self::KeyFeatures),
            "architecture" => Ok(Self::Architecture),
            "supported-sensors" => Ok(Self::SupportedSensors),
            _ => {
                Err(
                    "Invalid section name. Expected one of IndexSectionintroduction, what-is-ceratina, key-features, architecture, supported-sensors",
                )
            }
        }
    }
}
impl std::fmt::Display for IndexSection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => f.write_str(""),
            Self::Introduction => f.write_str("introduction"),
            Self::WhatIsCeratina => f.write_str("what-is-ceratina"),
            Self::KeyFeatures => f.write_str("key-features"),
            Self::Architecture => f.write_str("architecture"),
            Self::SupportedSensors => f.write_str("supported-sensors"),
        }
    }
}
#[component(no_case_check)]
pub fn Index(section: IndexSection) -> Element {
    rsx! {
        h1 { id : "introduction", Link { to : BookRoute::Index { section :
        IndexSection::Introduction, }, class : "header", "Introduction" } } p {
        "Ceratina is an open-source environmental data logger built on the ESP32-S3. It bridges the gap between embedded sensor hardware and modern web-based monitoring, providing a unified stack from bootloader to browser."
        } h2 { id : "what-is-ceratina", Link { to : BookRoute::Index { section :
        IndexSection::WhatIsCeratina, }, class : "header", "What is Ceratina?" } } p {
        "Ceratina is a data logging platform by " Link { to :
        "https://www.apidaesystems.ca", "Apidae Systems" }
        " designed for environmental monitoring. It collects temperature, humidity, voltage, and other sensor data through an I2C mux, and serves it via a real-time web dashboard."
        } h2 { id : "key-features", Link { to : BookRoute::Index { section :
        IndexSection::KeyFeatures, }, class : "header", "Key Features" } } ul { li {
        strong { "Multi-sensor support" }
        " via TCA9548A I2C multiplexer (up to 8 sensor channels)" } li { strong {
        "Real-time web dashboard" } " with live data streaming via CloudEvents" } li {
        strong { "Browser-based terminal" } " for device management over WebSocket" } li
        { strong { "SSH access" } " with MicroShell virtual filesystem" } li { strong {
        "WiFi provisioning" } " with captive portal and access point fallback" } li {
        strong { "SD card and LittleFS" } " dual filesystem support" } li { strong {
        "CSV export" } " for all sensor data directly from the browser" } li { strong {
        "OTA-ready" } " firmware architecture on PlatformIO + Arduino" } } h2 { id :
        "architecture", Link { to : BookRoute::Index { section :
        IndexSection::Architecture, }, class : "header", "Architecture" } } CodeBlock {
        contents :
        "<pre style=\"background-color:#0d0d0d;\">\n<span style=\"color:#f8f8f2;\">Browser (Dioxus WASM)\n</span><span style=\"color:#f8f8f2;\">    ↕ HTTP/WebSocket\n</span><span style=\"color:#f8f8f2;\">ESP32-S3 Firmware (PlatformIO C++)\n</span><span style=\"color:#f8f8f2;\">    ↕ I2C / SPI / UART\n</span><span style=\"color:#f8f8f2;\">Sensors &amp; Peripherals</span></pre>\n",
        light_contents :
        "<pre style=\"background-color:#ffffff;\">\n<span style=\"color:#0d0d0d;\">Browser (Dioxus WASM)\n</span><span style=\"color:#0d0d0d;\">    ↕ HTTP/WebSocket\n</span><span style=\"color:#0d0d0d;\">ESP32-S3 Firmware (PlatformIO C++)\n</span><span style=\"color:#0d0d0d;\">    ↕ I2C / SPI / UART\n</span><span style=\"color:#0d0d0d;\">Sensors &amp; Peripherals</span></pre>\n",
        } p { "The system is split into three layers:" } ol { li { strong { "Firmware" }
        " (" code { "src/" }
        ") — PlatformIO C++ with Arduino framework, ESPAsyncWebServer, MicroShell, LibSSH"
        } li { strong { "Web App" } " (" code { "web/" }
        ") — Dioxus 0.7 fullstack app compiled to WASM" } li { strong { "Hardware" }
        " — Custom carrier board with TCA9548A mux, DS3231 RTC, AT24C32 EEPROM, Neopixel status LED"
        } } h2 { id : "supported-sensors", Link { to : BookRoute::Index { section :
        IndexSection::SupportedSensors, }, class : "header", "Supported Sensors" } }
        table { thead { th { "Sensor" } th { "Type" } th { "Interface" } th { "Address" }
        } tr { th { "CHT832X (SEN0546)" } th { "Temperature & Humidity" } th {
        "I2C via mux" } th { "0x44" } } tr { th { "ADS1115" } th {
        "4-channel voltage monitor" } th { "I2C via mux" } th { "0x48" } } tr { th {
        "DS3231" } th { "Real-time clock" } th { "I2C direct" } th { "0x68" } } tr { th {
        "AT24C32" } th { "4KB EEPROM" } th { "I2C direct" } th { "0x50" } } tr { th {
        "SCD30 / SCD4x" } th { "CO2 + T&H" } th { "I2C" } th { "0x61 / 0x62" } } }
    }
}
#[derive(
    Clone,
    Copy,
    PartialEq,
    Eq,
    Hash,
    Debug,
    Default,
    serde::Serialize,
    serde::Deserialize
)]
pub enum GettingStartedSection {
    #[default]
    Empty,
    GettingStarted,
    Prerequisites,
    FlashingTheFirmware,
    Connecting,
    RunningTests,
}
impl std::str::FromStr for GettingStartedSection {
    type Err = &'static str;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "" => Ok(Self::Empty),
            "getting-started" => Ok(Self::GettingStarted),
            "prerequisites" => Ok(Self::Prerequisites),
            "flashing-the-firmware" => Ok(Self::FlashingTheFirmware),
            "connecting" => Ok(Self::Connecting),
            "running-tests" => Ok(Self::RunningTests),
            _ => {
                Err(
                    "Invalid section name. Expected one of GettingStartedSectiongetting-started, prerequisites, flashing-the-firmware, connecting, running-tests",
                )
            }
        }
    }
}
impl std::fmt::Display for GettingStartedSection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => f.write_str(""),
            Self::GettingStarted => f.write_str("getting-started"),
            Self::Prerequisites => f.write_str("prerequisites"),
            Self::FlashingTheFirmware => f.write_str("flashing-the-firmware"),
            Self::Connecting => f.write_str("connecting"),
            Self::RunningTests => f.write_str("running-tests"),
        }
    }
}
#[component(no_case_check)]
pub fn GettingStarted(section: GettingStartedSection) -> Element {
    rsx! {
        h1 { id : "getting-started", Link { to : BookRoute::GettingStarted { section :
        GettingStartedSection::GettingStarted, }, class : "header", "Getting Started" } }
        h2 { id : "prerequisites", Link { to : BookRoute::GettingStarted { section :
        GettingStartedSection::Prerequisites, }, class : "header", "Prerequisites" } } ul
        { li { Link { to : "https://platformio.org/", "PlatformIO" }
        " CLI or IDE extension" } li {
        "ESP32-S3 development board with the Ceratina carrier board" } li {
        "USB-C cable for flashing" } } h2 { id : "flashing-the-firmware", Link { to :
        BookRoute::GettingStarted { section : GettingStartedSection::FlashingTheFirmware,
        }, class : "header", "Flashing the Firmware" } } p {
        "Set your WiFi credentials as environment variables:" } CodeBlock { contents :
        "<pre style=\"background-color:#0d0d0d;\">\n<span style=\"color:#f8f8f2;\">export WIFI_SSID=your_network\n</span><span style=\"color:#f8f8f2;\">export WIFI_PASSWORD=your_password</span></pre>\n",
        light_contents :
        "<pre style=\"background-color:#ffffff;\">\n<span style=\"color:#0d0d0d;\">export WIFI_SSID=your_network\n</span><span style=\"color:#0d0d0d;\">export WIFI_PASSWORD=your_password</span></pre>\n",
        } p { "Build and flash:" } CodeBlock { contents :
        "<pre style=\"background-color:#0d0d0d;\">\n<span style=\"color:#f8f8f2;\">pio run --target upload</span></pre>\n",
        light_contents :
        "<pre style=\"background-color:#ffffff;\">\n<span style=\"color:#0d0d0d;\">pio run --target upload</span></pre>\n",
        } p { "The device will:" } ol { li { "Power on the I2C sensor relay" } li {
        "Initialize the TCA9548A mux and discover sensors" } li {
        "Start the access point (" code { "ceratina-access-point" } ")" } li {
        "Attempt to connect to your WiFi network" } li {
        "Start the HTTP server, SSH server, and WebSocket shell" } } h2 { id :
        "connecting", Link { to : BookRoute::GettingStarted { section :
        GettingStartedSection::Connecting, }, class : "header", "Connecting" } } p {
        "Once connected to WiFi, the device is reachable at:" } ul { li { strong {
        "Web dashboard" } ": " code { "http://ceratina.local" } } li { strong { "SSH" }
        ": " code { "ssh $USER@ceratina.local" } } li { strong { "WebSocket shell" } ": "
        code { "ws://ceratina.local/ws/shell" } } } p {
        "If WiFi is not configured, connect to the  " code { "ceratina-access-point" }
        " WiFi network (password:  " code { "apidaesystems" } ") and navigate to  " code
        { "http://192.168.4.1" } "." } h2 { id : "running-tests", Link { to :
        BookRoute::GettingStarted { section : GettingStartedSection::RunningTests, },
        class : "header", "Running Tests" } } CodeBlock { contents :
        "<pre style=\"background-color:#0d0d0d;\">\n<span style=\"color:#f8f8f2;\">pio test</span></pre>\n",
        light_contents :
        "<pre style=\"background-color:#ffffff;\">\n<span style=\"color:#0d0d0d;\">pio test</span></pre>\n",
        } p { "Tests run on-device via UART. The custom test runner auto-discovers all  "
        code { "*_run_tests()" } " functions and generates a Unity test harness." }
    }
}
#[derive(
    Clone,
    Copy,
    PartialEq,
    Eq,
    Hash,
    Debug,
    Default,
    serde::Serialize,
    serde::Deserialize
)]
pub enum HardwareSection {
    #[default]
    Empty,
    Hardware,
    CeratinaCarrierBoard,
    I2CBusLayout,
    GpioAssignments,
    NeopixelStatusLed,
}
impl std::str::FromStr for HardwareSection {
    type Err = &'static str;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "" => Ok(Self::Empty),
            "hardware" => Ok(Self::Hardware),
            "ceratina-carrier-board" => Ok(Self::CeratinaCarrierBoard),
            "i2c-bus-layout" => Ok(Self::I2CBusLayout),
            "gpio-assignments" => Ok(Self::GpioAssignments),
            "neopixel-status-led" => Ok(Self::NeopixelStatusLed),
            _ => {
                Err(
                    "Invalid section name. Expected one of HardwareSectionhardware, ceratina-carrier-board, i2c-bus-layout, gpio-assignments, neopixel-status-led",
                )
            }
        }
    }
}
impl std::fmt::Display for HardwareSection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => f.write_str(""),
            Self::Hardware => f.write_str("hardware"),
            Self::CeratinaCarrierBoard => f.write_str("ceratina-carrier-board"),
            Self::I2CBusLayout => f.write_str("i2c-bus-layout"),
            Self::GpioAssignments => f.write_str("gpio-assignments"),
            Self::NeopixelStatusLed => f.write_str("neopixel-status-led"),
        }
    }
}
#[component(no_case_check)]
pub fn Hardware(section: HardwareSection) -> Element {
    rsx! {
        h1 { id : "hardware", Link { to : BookRoute::Hardware { section :
        HardwareSection::Hardware, }, class : "header", "Hardware" } } h2 { id :
        "ceratina-carrier-board", Link { to : BookRoute::Hardware { section :
        HardwareSection::CeratinaCarrierBoard, }, class : "header",
        "Ceratina Carrier Board" } } p {
        "The carrier board connects an ESP32-S3 to external sensors via a TCA9548A I2C multiplexer. Each of the 8 mux channels is routed to a D-SUB 9-pin connector for plug-and-play sensor modules."
        } h2 { id : "i2c-bus-layout", Link { to : BookRoute::Hardware { section :
        HardwareSection::I2CBusLayout, }, class : "header", "I2C Bus Layout" } } table {
        thead { th { "Bus" } th { "Devices" } th { "Notes" } } tr { th {
        "Wire0 (GPIO 15/16)" } th { "DS3231 RTC" } th { "Always-on, coin cell backed" } }
        tr { th { "Wire1 (GPIO 17/18)" } th {
        "TCA9548A mux (0x70), AT24C32 EEPROM (0x50)" } th { "Direct on bus" } } tr { th {
        "Wire1 via mux ch0-7" } th { "CHT832X, ADS1115, etc." } th { "Behind relay power"
        } } } h2 { id : "gpio-assignments", Link { to : BookRoute::Hardware { section :
        HardwareSection::GpioAssignments, }, class : "header", "GPIO Assignments" } }
        table { thead { th { "GPIO" } th { "Function" } } tr { th { "5" } th {
        "I2C sensor relay power" } } tr { th { "10" } th { "SD card chip select (SPI)" }
        } tr { th { "15" } th { "I2C Bus 0 SDA" } } tr { th { "16" } th { "I2C Bus 0 SCL"
        } } tr { th { "17" } th { "I2C Bus 1 SDA" } } tr { th { "18" } th {
        "I2C Bus 1 SCL" } } tr { th { "38" } th { "Neopixel data" } } } h2 { id :
        "neopixel-status-led", Link { to : BookRoute::Hardware { section :
        HardwareSection::NeopixelStatusLed, }, class : "header", "Neopixel Status LED" }
        } table { thead { th { "Color" } th { "Meaning" } } tr { th { "Blue" } th {
        "Booting" } } tr { th { "Red" } th { "LittleFS formatting" } } tr { th { "Green"
        } th { "WiFi connected" } } tr { th { "Yellow" } th {
        "WiFi disconnected / AP only" } } tr { th { "White" } th { "SSH client connected"
        } } tr { th { "Magenta" } th { "Custom (via " code { "/dev/led" } ")" } } }
    }
}
#[derive(
    Clone,
    Copy,
    PartialEq,
    Eq,
    Hash,
    Debug,
    Default,
    serde::Serialize,
    serde::Deserialize
)]
pub enum FirmwareSection {
    #[default]
    Empty,
    Firmware,
    ProjectStructure,
    Configuration,
    Testing,
}
impl std::str::FromStr for FirmwareSection {
    type Err = &'static str;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "" => Ok(Self::Empty),
            "firmware" => Ok(Self::Firmware),
            "project-structure" => Ok(Self::ProjectStructure),
            "configuration" => Ok(Self::Configuration),
            "testing" => Ok(Self::Testing),
            _ => {
                Err(
                    "Invalid section name. Expected one of FirmwareSectionfirmware, project-structure, configuration, testing",
                )
            }
        }
    }
}
impl std::fmt::Display for FirmwareSection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => f.write_str(""),
            Self::Firmware => f.write_str("firmware"),
            Self::ProjectStructure => f.write_str("project-structure"),
            Self::Configuration => f.write_str("configuration"),
            Self::Testing => f.write_str("testing"),
        }
    }
}
#[component(no_case_check)]
pub fn Firmware(section: FirmwareSection) -> Element {
    rsx! {
        h1 { id : "firmware", Link { to : BookRoute::Firmware { section :
        FirmwareSection::Firmware, }, class : "header", "Firmware" } } h2 { id :
        "project-structure", Link { to : BookRoute::Firmware { section :
        FirmwareSection::ProjectStructure, }, class : "header", "Project Structure" } }
        CodeBlock { contents :
        "<pre style=\"background-color:#0d0d0d;\">\n<span style=\"color:#f8f8f2;\">src/\n</span><span style=\"color:#f8f8f2;\">  config.h              Central CONFIG_ constants\n</span><span style=\"color:#f8f8f2;\">  main.cpp              Boot orchestration, service loop\n</span><span style=\"color:#f8f8f2;\">  console/\n</span><span style=\"color:#f8f8f2;\">    icons.h             Nerd Font glyph constants\n</span><span style=\"color:#f8f8f2;\">    colors.h            ANSI escape + RGB color constants\n</span><span style=\"color:#f8f8f2;\">  drivers/\n</span><span style=\"color:#f8f8f2;\">    ads1115.cpp         ADS1115 voltage monitor (auto-discovers mux channel)\n</span><span style=\"color:#f8f8f2;\">    ds3231.cpp          DS3231 RTC\n</span><span style=\"color:#f8f8f2;\">    neopixel.cpp        Adafruit NeoPixel wrapper\n</span><span style=\"color:#f8f8f2;\">    tca9548a.cpp        TCA9548A I2C mux\n</span><span style=\"color:#f8f8f2;\">  networking/\n</span><span style=\"color:#f8f8f2;\">    wifi.cpp            STA + AP mode, DNS captive portal, NVS credentials\n</span><span style=\"color:#f8f8f2;\">    sntp.cpp            NTP time sync with DS3231 update\n</span><span style=\"color:#f8f8f2;\">  programs/\n</span><span style=\"color:#f8f8f2;\">    shell/\n</span><span style=\"color:#f8f8f2;\">      shell.cpp         MicroShell init, hostname management\n</span><span style=\"color:#f8f8f2;\">      commands.cpp      reboot, reset, exit, wifi-set, wifi-connect\n</span><span style=\"color:#f8f8f2;\">      fs/               Virtual filesystem mounts (/dev, /etc, /bin, etc.)\n</span><span style=\"color:#f8f8f2;\">    ssh/\n</span><span style=\"color:#f8f8f2;\">      ssh_server.cpp    LibSSH callback-based SSH server\n</span><span style=\"color:#f8f8f2;\">      ssh_client.cpp    ssh-exec, scp-get, scp-put, ota commands\n</span><span style=\"color:#f8f8f2;\">  services/\n</span><span style=\"color:#f8f8f2;\">    http.cpp            ESPAsyncWebServer, all API routes, captive portal\n</span><span style=\"color:#f8f8f2;\">    cloudevents.cpp     CloudEvents batch endpoint\n</span><span style=\"color:#f8f8f2;\">    ws_shell.cpp        WebSocket-to-MicroShell bridge\n</span><span style=\"color:#f8f8f2;\">    temperature_and_humidity.cpp  CHT832X sensor service\n</span><span style=\"color:#f8f8f2;\">    eeprom.cpp          AT24C32 EEPROM driver\n</span><span style=\"color:#f8f8f2;\">  testing/\n</span><span style=\"color:#f8f8f2;\">    it.h                Screenplay test pattern macro</span></pre>\n",
        light_contents :
        "<pre style=\"background-color:#ffffff;\">\n<span style=\"color:#0d0d0d;\">src/\n</span><span style=\"color:#0d0d0d;\">  config.h              Central CONFIG_ constants\n</span><span style=\"color:#0d0d0d;\">  main.cpp              Boot orchestration, service loop\n</span><span style=\"color:#0d0d0d;\">  console/\n</span><span style=\"color:#0d0d0d;\">    icons.h             Nerd Font glyph constants\n</span><span style=\"color:#0d0d0d;\">    colors.h            ANSI escape + RGB color constants\n</span><span style=\"color:#0d0d0d;\">  drivers/\n</span><span style=\"color:#0d0d0d;\">    ads1115.cpp         ADS1115 voltage monitor (auto-discovers mux channel)\n</span><span style=\"color:#0d0d0d;\">    ds3231.cpp          DS3231 RTC\n</span><span style=\"color:#0d0d0d;\">    neopixel.cpp        Adafruit NeoPixel wrapper\n</span><span style=\"color:#0d0d0d;\">    tca9548a.cpp        TCA9548A I2C mux\n</span><span style=\"color:#0d0d0d;\">  networking/\n</span><span style=\"color:#0d0d0d;\">    wifi.cpp            STA + AP mode, DNS captive portal, NVS credentials\n</span><span style=\"color:#0d0d0d;\">    sntp.cpp            NTP time sync with DS3231 update\n</span><span style=\"color:#0d0d0d;\">  programs/\n</span><span style=\"color:#0d0d0d;\">    shell/\n</span><span style=\"color:#0d0d0d;\">      shell.cpp         MicroShell init, hostname management\n</span><span style=\"color:#0d0d0d;\">      commands.cpp      reboot, reset, exit, wifi-set, wifi-connect\n</span><span style=\"color:#0d0d0d;\">      fs/               Virtual filesystem mounts (/dev, /etc, /bin, etc.)\n</span><span style=\"color:#0d0d0d;\">    ssh/\n</span><span style=\"color:#0d0d0d;\">      ssh_server.cpp    LibSSH callback-based SSH server\n</span><span style=\"color:#0d0d0d;\">      ssh_client.cpp    ssh-exec, scp-get, scp-put, ota commands\n</span><span style=\"color:#0d0d0d;\">  services/\n</span><span style=\"color:#0d0d0d;\">    http.cpp            ESPAsyncWebServer, all API routes, captive portal\n</span><span style=\"color:#0d0d0d;\">    cloudevents.cpp     CloudEvents batch endpoint\n</span><span style=\"color:#0d0d0d;\">    ws_shell.cpp        WebSocket-to-MicroShell bridge\n</span><span style=\"color:#0d0d0d;\">    temperature_and_humidity.cpp  CHT832X sensor service\n</span><span style=\"color:#0d0d0d;\">    eeprom.cpp          AT24C32 EEPROM driver\n</span><span style=\"color:#0d0d0d;\">  testing/\n</span><span style=\"color:#0d0d0d;\">    it.h                Screenplay test pattern macro</span></pre>\n",
        } h2 { id : "configuration", Link { to : BookRoute::Firmware { section :
        FirmwareSection::Configuration, }, class : "header", "Configuration" } } p {
        "All constants are in  " code { "src/config.h" } " with  " code { "CONFIG_" }
        " prefix and  " code { "#ifndef" }
        " guards for build-flag override. Key sections:" } ul { li {
        "Deployment (hostname, platform)" } li { "Neopixel (GPIO, brightness)" } li {
        "SSH (port, hostkey paths, buffer sizes)" } li {
        "WiFi (timeout, NVS namespace, AP credentials)" } li {
        "I2C (bus GPIOs, frequency, mux address)" } li {
        "Sensors (T&H address, voltage monitor channels)" } li {
        "CloudEvents (tenant, site)" } } h2 { id : "testing", Link { to :
        BookRoute::Firmware { section : FirmwareSection::Testing, }, class : "header",
        "Testing" } } p { "Tests use the Unity framework with a screenplay pattern ( "
        code { "it()" } " macro). The custom test runner ( " code {
        "tests/test_custom_runner.py" } ") auto-discovers  " code { "*_run_tests()" }
        " functions in  " code { "src/" } " and generates  " code {
        "tests/test_unit/main.cpp" } "." } CodeBlock { contents :
        "<pre style=\"background-color:#0d0d0d;\">\n<span style=\"color:#f8f8f2;\">pio test              # Run all tests\n</span><span style=\"color:#f8f8f2;\">pio test -v           # Verbose output</span></pre>\n",
        light_contents :
        "<pre style=\"background-color:#ffffff;\">\n<span style=\"color:#0d0d0d;\">pio test              # Run all tests\n</span><span style=\"color:#0d0d0d;\">pio test -v           # Verbose output</span></pre>\n",
        } p {
        "Tests save and restore NVS state so WiFi credentials persist across test runs."
        }
    }
}
#[derive(
    Clone,
    Copy,
    PartialEq,
    Eq,
    Hash,
    Debug,
    Default,
    serde::Serialize,
    serde::Deserialize
)]
pub enum WebDashboardSection {
    #[default]
    Empty,
    WebDashboard,
    Panels,
    Measurements,
    Terminal,
    Network,
    Filesystem,
    Polling,
    DeviceUrl,
}
impl std::str::FromStr for WebDashboardSection {
    type Err = &'static str;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "" => Ok(Self::Empty),
            "web-dashboard" => Ok(Self::WebDashboard),
            "panels" => Ok(Self::Panels),
            "measurements" => Ok(Self::Measurements),
            "terminal" => Ok(Self::Terminal),
            "network" => Ok(Self::Network),
            "filesystem" => Ok(Self::Filesystem),
            "polling" => Ok(Self::Polling),
            "device-url" => Ok(Self::DeviceUrl),
            _ => {
                Err(
                    "Invalid section name. Expected one of WebDashboardSectionweb-dashboard, panels, measurements, terminal, network, filesystem, polling, device-url",
                )
            }
        }
    }
}
impl std::fmt::Display for WebDashboardSection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => f.write_str(""),
            Self::WebDashboard => f.write_str("web-dashboard"),
            Self::Panels => f.write_str("panels"),
            Self::Measurements => f.write_str("measurements"),
            Self::Terminal => f.write_str("terminal"),
            Self::Network => f.write_str("network"),
            Self::Filesystem => f.write_str("filesystem"),
            Self::Polling => f.write_str("polling"),
            Self::DeviceUrl => f.write_str("device-url"),
        }
    }
}
#[component(no_case_check)]
pub fn WebDashboard(section: WebDashboardSection) -> Element {
    rsx! {
        h1 { id : "web-dashboard", Link { to : BookRoute::WebDashboard { section :
        WebDashboardSection::WebDashboard, }, class : "header", "Web Dashboard" } } p {
        "The web dashboard is a Dioxus 0.7 fullstack app compiled to WASM. It runs in the browser and communicates with the device over HTTP and WebSocket."
        } h2 { id : "panels", Link { to : BookRoute::WebDashboard { section :
        WebDashboardSection::Panels, }, class : "header", "Panels" } } h3 { id :
        "measurements", Link { to : BookRoute::WebDashboard { section :
        WebDashboardSection::Measurements, }, class : "header", "Measurements" } } p {
        "Tabbed interface with three sensor views:" } ul { li { strong { "Temp/Humidity"
        } " — CHT832X readings from mux channels, with per-sensor columns" } li {
        strong { "Voltage" } " — ADS1115 4-channel readings with gain display" } li {
        strong { "CO2" }
        " — SCD30/SCD4x PPM, temperature, humidity with inline config controls" } } p {
        "Each tab has CSV export and a Sample button (Ctrl+Enter shortcut)." } h3 { id :
        "terminal", Link { to : BookRoute::WebDashboard { section :
        WebDashboardSection::Terminal, }, class : "header", "Terminal" } } p {
        "Browser-based shell powered by xterm.js over WebSocket ( " code { "/ws/shell" }
        "). Provides the same MicroShell experience as SSH — browse the virtual filesystem, read sensors, manage WiFi, reboot the device."
        } h3 { id : "network", Link { to : BookRoute::WebDashboard { section :
        WebDashboardSection::Network, }, class : "header", "Network" } } p {
        "WiFi scan, connect, and AP configuration. Shows connected SSID, RSSI, and IP in the status bar."
        } h3 { id : "filesystem", Link { to : BookRoute::WebDashboard { section :
        WebDashboardSection::Filesystem, }, class : "header", "Filesystem" } } p {
        "Browse and manage files on SD card and LittleFS. Delete files, download from SD, and view storage usage with progress bars."
        } h2 { id : "polling", Link { to : BookRoute::WebDashboard { section :
        WebDashboardSection::Polling, }, class : "header", "Polling" } } p {
        "The dashboard polls the device every 5 seconds via  " code { "/api/cloudevents"
        }
        ". Sensor readings are deduplicated by event timestamp and value comparison to avoid redundant rows. The polling coroutine skips cycles when a manual sample is in progress."
        } h2 { id : "device-url", Link { to : BookRoute::WebDashboard { section :
        WebDashboardSection::DeviceUrl, }, class : "header", "Device URL" } } p {
        "The device URL defaults to  " code { "http://ceratina.local" }
        " (mDNS). It can be changed in the URL bar and persists in localStorage. The status badge shows the device IP when connected, with SSID and RSSI on hover."
        }
    }
}
#[derive(
    Clone,
    Copy,
    PartialEq,
    Eq,
    Hash,
    Debug,
    Default,
    serde::Serialize,
    serde::Deserialize
)]
pub enum ShellCommandsSection {
    #[default]
    Empty,
    ShellCommands,
    Commands,
    VirtualFilesystem,
    Examples,
}
impl std::str::FromStr for ShellCommandsSection {
    type Err = &'static str;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "" => Ok(Self::Empty),
            "shell-commands" => Ok(Self::ShellCommands),
            "commands" => Ok(Self::Commands),
            "virtual-filesystem" => Ok(Self::VirtualFilesystem),
            "examples" => Ok(Self::Examples),
            _ => {
                Err(
                    "Invalid section name. Expected one of ShellCommandsSectionshell-commands, commands, virtual-filesystem, examples",
                )
            }
        }
    }
}
impl std::fmt::Display for ShellCommandsSection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => f.write_str(""),
            Self::ShellCommands => f.write_str("shell-commands"),
            Self::Commands => f.write_str("commands"),
            Self::VirtualFilesystem => f.write_str("virtual-filesystem"),
            Self::Examples => f.write_str("examples"),
        }
    }
}
#[component(no_case_check)]
pub fn ShellCommands(section: ShellCommandsSection) -> Element {
    rsx! {
        h1 { id : "shell-commands", Link { to : BookRoute::ShellCommands { section :
        ShellCommandsSection::ShellCommands, }, class : "header", "Shell Commands" } } p
        {
        "The MicroShell virtual filesystem is accessible via SSH or the browser terminal."
        } h2 { id : "commands", Link { to : BookRoute::ShellCommands { section :
        ShellCommandsSection::Commands, }, class : "header", "Commands" } } table { thead
        { th { "Command" } th { "Description" } } tr { th { code { "help" } } th {
        "List all commands" } } tr { th { code { "ls" } } th { "List directory contents"
        } } tr { th { code { "cd <path>" } } th { "Change directory" } } tr { th { code {
        "cat <file>" } } th { "Read file contents" } } tr { th { code {
        "echo <text> > <file>" } } th { "Write to file" } } tr { th { code { "reboot" } }
        th { "Reboot the device" } } tr { th { code { "reset" } } th {
        "Reset shell state" } } tr { th { code { "exit" } } th { "Close SSH session" } }
        tr { th { code { "wifi-set <ssid> <password>" } } th {
        "Save WiFi credentials to NVS" } } tr { th { code { "wifi-connect" } } th {
        "Connect to saved WiFi network" } } tr { th { code {
        "ssh-exec <host> <user> <pass> <cmd>" } } th { "Execute command on remote host" }
        } tr { th { code { "scp-get <host> <user> <pass> <remote> <local>" } } th {
        "Download file from remote host" } } tr { th { code {
        "scp-put <host> <user> <pass> <local> <remote>" } } th {
        "Upload file to remote host" } } tr { th { code {
        "ota <host> <user> <pass> <firmware-path>" } } th { "OTA firmware update via SCP"
        } } } h2 { id : "virtual-filesystem", Link { to : BookRoute::ShellCommands {
        section : ShellCommandsSection::VirtualFilesystem, }, class : "header",
        "Virtual Filesystem" } } CodeBlock { contents :
        "<pre style=\"background-color:#0d0d0d;\">\n<span style=\"color:#f8f8f2;\">/\n</span><span style=\"color:#f8f8f2;\">  bin/                  Commands (reboot, wifi-set, etc.)\n</span><span style=\"color:#f8f8f2;\">  dev/\n</span><span style=\"color:#f8f8f2;\">    null                Discard sink\n</span><span style=\"color:#f8f8f2;\">    random              Hardware RNG (esp_random)\n</span><span style=\"color:#f8f8f2;\">    uptime              System uptime\n</span><span style=\"color:#f8f8f2;\">    heap                Heap memory usage\n</span><span style=\"color:#f8f8f2;\">    time                Local time (NTP-synced)\n</span><span style=\"color:#f8f8f2;\">    led                 Neopixel control (write: off/red/green/blue/yellow/magenta/cyan/white)\n</span><span style=\"color:#f8f8f2;\">    bus/\n</span><span style=\"color:#f8f8f2;\">      i2c0              I2C bus 0 scan\n</span><span style=\"color:#f8f8f2;\">      i2c1              I2C bus 1 scan\n</span><span style=\"color:#f8f8f2;\">      mux               TCA9548A mux scan (all channels)\n</span><span style=\"color:#f8f8f2;\">    sensors/\n</span><span style=\"color:#f8f8f2;\">      i2c_scan          Full I2C device scan\n</span><span style=\"color:#f8f8f2;\">      rtc               DS3231 time + oscillator status\n</span><span style=\"color:#f8f8f2;\">      temperature       DS3231 temperature\n</span><span style=\"color:#f8f8f2;\">    sd/\n</span><span style=\"color:#f8f8f2;\">      info              SD card mount info\n</span><span style=\"color:#f8f8f2;\">    ssh/\n</span><span style=\"color:#f8f8f2;\">      fingerprint       SSH host key fingerprint\n</span><span style=\"color:#f8f8f2;\">    mem/                Memory info\n</span><span style=\"color:#f8f8f2;\">  etc/\n</span><span style=\"color:#f8f8f2;\">    hostname            Read/write hostname\n</span><span style=\"color:#f8f8f2;\">    config              CPU, flash, SDK info\n</span><span style=\"color:#f8f8f2;\">    wifi                Read/write WiFi credentials (ssid:password)\n</span><span style=\"color:#f8f8f2;\">    user                Current SSH user</span></pre>\n",
        light_contents :
        "<pre style=\"background-color:#ffffff;\">\n<span style=\"color:#0d0d0d;\">/\n</span><span style=\"color:#0d0d0d;\">  bin/                  Commands (reboot, wifi-set, etc.)\n</span><span style=\"color:#0d0d0d;\">  dev/\n</span><span style=\"color:#0d0d0d;\">    null                Discard sink\n</span><span style=\"color:#0d0d0d;\">    random              Hardware RNG (esp_random)\n</span><span style=\"color:#0d0d0d;\">    uptime              System uptime\n</span><span style=\"color:#0d0d0d;\">    heap                Heap memory usage\n</span><span style=\"color:#0d0d0d;\">    time                Local time (NTP-synced)\n</span><span style=\"color:#0d0d0d;\">    led                 Neopixel control (write: off/red/green/blue/yellow/magenta/cyan/white)\n</span><span style=\"color:#0d0d0d;\">    bus/\n</span><span style=\"color:#0d0d0d;\">      i2c0              I2C bus 0 scan\n</span><span style=\"color:#0d0d0d;\">      i2c1              I2C bus 1 scan\n</span><span style=\"color:#0d0d0d;\">      mux               TCA9548A mux scan (all channels)\n</span><span style=\"color:#0d0d0d;\">    sensors/\n</span><span style=\"color:#0d0d0d;\">      i2c_scan          Full I2C device scan\n</span><span style=\"color:#0d0d0d;\">      rtc               DS3231 time + oscillator status\n</span><span style=\"color:#0d0d0d;\">      temperature       DS3231 temperature\n</span><span style=\"color:#0d0d0d;\">    sd/\n</span><span style=\"color:#0d0d0d;\">      info              SD card mount info\n</span><span style=\"color:#0d0d0d;\">    ssh/\n</span><span style=\"color:#0d0d0d;\">      fingerprint       SSH host key fingerprint\n</span><span style=\"color:#0d0d0d;\">    mem/                Memory info\n</span><span style=\"color:#0d0d0d;\">  etc/\n</span><span style=\"color:#0d0d0d;\">    hostname            Read/write hostname\n</span><span style=\"color:#0d0d0d;\">    config              CPU, flash, SDK info\n</span><span style=\"color:#0d0d0d;\">    wifi                Read/write WiFi credentials (ssid:password)\n</span><span style=\"color:#0d0d0d;\">    user                Current SSH user</span></pre>\n",
        } h2 { id : "examples", Link { to : BookRoute::ShellCommands { section :
        ShellCommandsSection::Examples, }, class : "header", "Examples" } } CodeBlock {
        contents :
        "<pre style=\"background-color:#0d0d0d;\">\n<span style=\"color:#f8f8f2;\">cat /dev/heap           # Show heap memory\n</span><span style=\"color:#f8f8f2;\">cat /dev/time           # Show current time\n</span><span style=\"color:#f8f8f2;\">echo red &gt; /dev/led     # Set neopixel to red\n</span><span style=\"color:#f8f8f2;\">cat /dev/bus/mux        # Scan all mux channels\n</span><span style=\"color:#f8f8f2;\">cat /etc/hostname       # Read hostname\n</span><span style=\"color:#f8f8f2;\">echo ceratina &gt; /etc/hostname  # Set hostname</span></pre>\n",
        light_contents :
        "<pre style=\"background-color:#ffffff;\">\n<span style=\"color:#0d0d0d;\">cat /dev/heap           # Show heap memory\n</span><span style=\"color:#0d0d0d;\">cat /dev/time           # Show current time\n</span><span style=\"color:#0d0d0d;\">echo red &gt; /dev/led     # Set neopixel to red\n</span><span style=\"color:#0d0d0d;\">cat /dev/bus/mux        # Scan all mux channels\n</span><span style=\"color:#0d0d0d;\">cat /etc/hostname       # Read hostname\n</span><span style=\"color:#0d0d0d;\">echo ceratina &gt; /etc/hostname  # Set hostname</span></pre>\n",
        }
    }
}
#[derive(
    Clone,
    Copy,
    PartialEq,
    Eq,
    Hash,
    Debug,
    Default,
    serde::Serialize,
    serde::Deserialize
)]
pub enum ApiReferenceSection {
    #[default]
    Empty,
    ApiReference,
    DeviceStatus,
    GetApistatus,
    GetApisystemdevicestatus,
    Sensors,
    GetApicloudevents,
    GetApico2Config,
    PostApico2Config,
    PostApico2StartPostApico2Stop,
    Wifi,
    GetApiwirelessstatus,
    PostApiwirelessactionsscan,
    PostApiwirelessactionsconnect,
    AccessPoint,
    GetApiapconfig,
    PostApiapconfig,
    Filesystem,
    GetApifilesystemlist,
    DeleteApifilesystemdelete,
    PostApiupload,
    GetApifiles,
    Websocket,
    Wsdevicewsshell,
}
impl std::str::FromStr for ApiReferenceSection {
    type Err = &'static str;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "" => Ok(Self::Empty),
            "api-reference" => Ok(Self::ApiReference),
            "device-status" => Ok(Self::DeviceStatus),
            "get-apistatus" => Ok(Self::GetApistatus),
            "get-apisystemdevicestatus" => Ok(Self::GetApisystemdevicestatus),
            "sensors" => Ok(Self::Sensors),
            "get-apicloudevents" => Ok(Self::GetApicloudevents),
            "get-apico2config" => Ok(Self::GetApico2Config),
            "post-apico2config" => Ok(Self::PostApico2Config),
            "post-apico2start--post-apico2stop" => {
                Ok(Self::PostApico2StartPostApico2Stop)
            }
            "wifi" => Ok(Self::Wifi),
            "get-apiwirelessstatus" => Ok(Self::GetApiwirelessstatus),
            "post-apiwirelessactionsscan" => Ok(Self::PostApiwirelessactionsscan),
            "post-apiwirelessactionsconnect" => Ok(Self::PostApiwirelessactionsconnect),
            "access-point" => Ok(Self::AccessPoint),
            "get-apiapconfig" => Ok(Self::GetApiapconfig),
            "post-apiapconfig" => Ok(Self::PostApiapconfig),
            "filesystem" => Ok(Self::Filesystem),
            "get-apifilesystemlist" => Ok(Self::GetApifilesystemlist),
            "delete-apifilesystemdelete" => Ok(Self::DeleteApifilesystemdelete),
            "post-apiupload" => Ok(Self::PostApiupload),
            "get-apifiles" => Ok(Self::GetApifiles),
            "websocket" => Ok(Self::Websocket),
            "wsdevicewsshell" => Ok(Self::Wsdevicewsshell),
            _ => {
                Err(
                    "Invalid section name. Expected one of ApiReferenceSectionapi-reference, device-status, get-apistatus, get-apisystemdevicestatus, sensors, get-apicloudevents, get-apico2config, post-apico2config, post-apico2start--post-apico2stop, wifi, get-apiwirelessstatus, post-apiwirelessactionsscan, post-apiwirelessactionsconnect, access-point, get-apiapconfig, post-apiapconfig, filesystem, get-apifilesystemlist, delete-apifilesystemdelete, post-apiupload, get-apifiles, websocket, wsdevicewsshell",
                )
            }
        }
    }
}
impl std::fmt::Display for ApiReferenceSection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => f.write_str(""),
            Self::ApiReference => f.write_str("api-reference"),
            Self::DeviceStatus => f.write_str("device-status"),
            Self::GetApistatus => f.write_str("get-apistatus"),
            Self::GetApisystemdevicestatus => f.write_str("get-apisystemdevicestatus"),
            Self::Sensors => f.write_str("sensors"),
            Self::GetApicloudevents => f.write_str("get-apicloudevents"),
            Self::GetApico2Config => f.write_str("get-apico2config"),
            Self::PostApico2Config => f.write_str("post-apico2config"),
            Self::PostApico2StartPostApico2Stop => {
                f.write_str("post-apico2start--post-apico2stop")
            }
            Self::Wifi => f.write_str("wifi"),
            Self::GetApiwirelessstatus => f.write_str("get-apiwirelessstatus"),
            Self::PostApiwirelessactionsscan => {
                f.write_str("post-apiwirelessactionsscan")
            }
            Self::PostApiwirelessactionsconnect => {
                f.write_str("post-apiwirelessactionsconnect")
            }
            Self::AccessPoint => f.write_str("access-point"),
            Self::GetApiapconfig => f.write_str("get-apiapconfig"),
            Self::PostApiapconfig => f.write_str("post-apiapconfig"),
            Self::Filesystem => f.write_str("filesystem"),
            Self::GetApifilesystemlist => f.write_str("get-apifilesystemlist"),
            Self::DeleteApifilesystemdelete => f.write_str("delete-apifilesystemdelete"),
            Self::PostApiupload => f.write_str("post-apiupload"),
            Self::GetApifiles => f.write_str("get-apifiles"),
            Self::Websocket => f.write_str("websocket"),
            Self::Wsdevicewsshell => f.write_str("wsdevicewsshell"),
        }
    }
}
#[component(no_case_check)]
pub fn ApiReference(section: ApiReferenceSection) -> Element {
    rsx! {
        h1 { id : "api-reference", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::ApiReference, }, class : "header", "API Reference" } } p {
        "All endpoints are served by the device's ESPAsyncWebServer on port 80." } h2 {
        id : "device-status", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::DeviceStatus, }, class : "header", "Device Status" } } h3 {
        id : "get-apistatus", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::GetApistatus, }, class : "header", "GET /api/status" } } p {
        "Basic device info (hostname, platform, uptime, heap, IP, RSSI)." } h3 { id :
        "get-apisystemdevicestatus", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::GetApisystemdevicestatus, }, class : "header",
        "GET /api/system/device/status" } } p {
        "CloudEvent-format status with nested device, network, runtime, and storage objects."
        } p { "Query params:  " code { "?location=sd|littlefs" } } h2 { id : "sensors",
        Link { to : BookRoute::ApiReference { section : ApiReferenceSection::Sensors, },
        class : "header", "Sensors" } } h3 { id : "get-apicloudevents", Link { to :
        BookRoute::ApiReference { section : ApiReferenceSection::GetApicloudevents, },
        class : "header", "GET /api/cloudevents" } } p { "Returns a CloudEvents batch ( "
        code { "application/cloudevents-batch+json" } ") with all sensor readings:" } ul
        { li { code { "status.v1" } " — heap, chip, IP, uptime" } li { code {
        "sensors.temperature_and_humidity.v1" } " — CHT832X readings per mux channel" }
        li { code { "sensors.power.v1" } " — ADS1115 voltage channels + gain" } } h3 {
        id : "get-apico2config", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::GetApico2Config, }, class : "header", "GET /api/co2/config"
        } } p {
        "CO2 sensor configuration (model, interval, calibration, offset, altitude)." } h3
        { id : "post-apico2config", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::PostApico2Config, }, class : "header",
        "POST /api/co2/config" } } p { "Set CO2 config. Body:  " code {
        "{{\"measurement_interval_seconds\": 5, \"auto_calibration_enabled\": true, ...}}"
        } } h3 { id : "post-apico2start--post-apico2stop", Link { to :
        BookRoute::ApiReference { section :
        ApiReferenceSection::PostApico2StartPostApico2Stop, }, class : "header",
        "POST /api/co2/start / POST /api/co2/stop" } } p {
        "Start or stop CO2 measurement." } h2 { id : "wifi", Link { to :
        BookRoute::ApiReference { section : ApiReferenceSection::Wifi, }, class :
        "header", "WiFi" } } h3 { id : "get-apiwirelessstatus", Link { to :
        BookRoute::ApiReference { section : ApiReferenceSection::GetApiwirelessstatus, },
        class : "header", "GET /api/wireless/status" } } p {
        "Connection state, STA SSID/IP/RSSI, AP state/SSID/IP." } h3 { id :
        "post-apiwirelessactionsscan", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::PostApiwirelessactionsscan, }, class : "header",
        "POST /api/wireless/actions/scan" } } p {
        "Scan for nearby WiFi networks. Returns SSID, RSSI, channel, encryption for each."
        } h3 { id : "post-apiwirelessactionsconnect", Link { to : BookRoute::ApiReference
        { section : ApiReferenceSection::PostApiwirelessactionsconnect, }, class :
        "header", "POST /api/wireless/actions/connect" } } p {
        "Connect to a network. Body:  " code {
        "{{\"ssid\": \"...\", \"password\": \"...\"}}" } } h2 { id : "access-point", Link
        { to : BookRoute::ApiReference { section : ApiReferenceSection::AccessPoint, },
        class : "header", "Access Point" } } h3 { id : "get-apiapconfig", Link { to :
        BookRoute::ApiReference { section : ApiReferenceSection::GetApiapconfig, }, class
        : "header", "GET /api/ap/config" } } p {
        "AP configuration (SSID, password, enabled state, active state, IP)." } h3 { id :
        "post-apiapconfig", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::PostApiapconfig, }, class : "header", "POST /api/ap/config"
        } } p { "Set AP config. Body:  " code {
        "{{\"ssid\": \"...\", \"password\": \"...\", \"enabled\": true}}" } } h2 { id :
        "filesystem", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::Filesystem, }, class : "header", "Filesystem" } } h3 { id :
        "get-apifilesystemlist", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::GetApifilesystemlist, }, class : "header",
        "GET /api/filesystem/list" } } p { "List files. Query params:  " code {
        "?location=sd|littlefs" } } h3 { id : "delete-apifilesystemdelete", Link { to :
        BookRoute::ApiReference { section :
        ApiReferenceSection::DeleteApifilesystemdelete, }, class : "header",
        "DELETE /api/filesystem/delete" } } p { "Delete a file. Query params:  " code {
        "?location=sd|littlefs&path=/filename" } } h3 { id : "post-apiupload", Link { to
        : BookRoute::ApiReference { section : ApiReferenceSection::PostApiupload, },
        class : "header", "POST /api/upload" } } p {
        "Upload file to SD card (multipart form data)." } h3 { id : "get-apifiles", Link
        { to : BookRoute::ApiReference { section : ApiReferenceSection::GetApifiles, },
        class : "header", "GET /api/files" } } p { "List SD card root directory." } h2 {
        id : "websocket", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::Websocket, }, class : "header", "WebSocket" } } h3 { id :
        "wsdevicewsshell", Link { to : BookRoute::ApiReference { section :
        ApiReferenceSection::Wsdevicewsshell, }, class : "header", "ws://device/ws/shell"
        } } p {
        "Interactive MicroShell session. Send text frames (keystrokes), receive text frames (terminal output with ANSI escape codes). Limited to 1 concurrent client."
        }
    }
}

use super::*;
