//! Device configuration for Microvisor.
//!
//! All deployment-specific values, hardware topology, and runtime
//! (flash-stored) credentials live in this single module. Edit this file
//! to customize your device, similar to NixOS's `configuration.nix`.
//!
//! Layout:
//! - Top-level: deployment constants (hostname, ports, platform, etc.)
//! - `time`, `wifi`, `ssh`, `http`, `ota`, `tcp_log`, `sd_card`, `ble`,
//!   `data_logger`: grouped deployment constants.
//! - `runtime`: WiFi credentials persisted in flash storage.
//! - `topology`: hardware bus and sensor topology for the current board.

// ─────────────────────────────────────────────────────────────────────────────
// Deployment constants
// ─────────────────────────────────────────────────────────────────────────────

/// Defaults to `"microvisor"`. Override via `HOSTNAME` env var.
pub const HOSTNAME: &str = {
    let h = option_env!("HOSTNAME");
    match h {
        Some(v) if !v.is_empty() => v,
        _ => "microvisor",
    }
};
pub const PLATFORM: &str = "esp32s3";

/// Defaults to `$USER` at compile time. Override via `SHELL_USER` env var.
pub const SSH_USER: &str = {
    let shell_user = option_env!("SHELL_USER");
    match shell_user {
        Some(u) if !u.is_empty() => u,
        _ => env!("USER"),
    }
};

/// SSH host key is generated at first boot and stored on SD card.
/// This path is relative to the user's home directory.
pub const SSH_HOST_KEY_FILE: &str = ".SSH/HOST_KEY";

pub const NTP_SERVER: &str = "pool.ntp.org";

pub mod sntp {
    pub const MAX_ATTEMPTS: usize = 3;
    pub const RETRY_INTERVAL_SECS: u64 = 60;
    pub const ATTEMPT_INTERVAL_SECS: u64 = 5;
}

pub mod time {
    /// IANA timezone name and UTC offset. Keep these in sync.
    pub const ZONE: &str = "America/Toronto";
    /// UTC offset in hours. EDT = -4, EST = -5.
    pub const UTC_OFFSET_HOURS: i64 = -4;
}

pub const ACTIVE_USER_KEY: &str = cloudevents::TENANT;

pub mod wifi {
    pub const CONNECT_TIMEOUT_SECS: u64 = 15;
    pub const RETRY_INTERVAL_SECS: u64 = 5;
    pub const FALLBACK_TO_AP: bool = true;

    pub mod ap {
        pub const SSID: &str = "ceratina-setup";
        pub const PASSWORD: &str = "changeme123";
        pub const CHANNEL: u8 = 6;
        pub const MAX_CONNECTIONS: u8 = 4;
        pub const AUTH_MODE: &str = "WPA2";
    }
}

pub mod ssh {
    pub const PORT: u16 = 22;
    pub const RX_BUF_SIZE: usize = 4096;
    pub const TX_BUF_SIZE: usize = 4096;
    pub const TIMEOUT_SECS: u64 = 300;
    /// When true, require key-based auth from ~/.ssh/authorized_keys.
    /// When false, accept any connection (AuthMethod::None).
    pub const REQUIRE_AUTH: bool = false;
}

pub mod http {
    pub const PORT: u16 = 80;
}

pub mod ota {
    pub const PORT: u16 = 3232;
    pub const RX_BUF_SIZE: usize = 16384;
    pub const TX_BUF_SIZE: usize = 16384;
    pub const CHUNK_SIZE: usize = 8192;
}

pub mod tcp_log {
    pub const PORT: u16 = 23;
    pub const RX_BUF_SIZE: usize = 4096;
    pub const TX_BUF_SIZE: usize = 4096;
    pub const INTERVAL_SECS: u64 = 1;
    pub const TIMEOUT_SECS: u64 = 5;
    pub const WELCOME: &[u8] = b"ceratina tcp log mirror connected\n";
}

pub mod i2c {
    pub struct BusConfig {
        pub sda_gpio: u8,
        pub scl_gpio: u8,
    }
    pub const FREQUENCY_KHZ: u32 = 100;
    pub const LEGACY_POWER_GPIO: u8 = 5;
    pub const BUS_0: BusConfig = BusConfig { sda_gpio: 8, scl_gpio: 9 };
    pub const BUS_1: BusConfig = BusConfig { sda_gpio: 17, scl_gpio: 18 };
    pub const MUX_ADDR: u8 = 0x70;
    pub const DIRECT_CHANNEL: i8 = -1;
    pub const ANY_MUX_CHANNEL: i8 = -2;
}

pub mod rs485 {
    pub struct BusConfig {
        pub tx_gpio: i8,
        pub rx_gpio: i8,
        pub de_re_gpio: i8,
        pub baud_rate: u32,
    }
    pub const BUS_0: BusConfig = BusConfig { tx_gpio: 45, rx_gpio: 48, de_re_gpio: 47, baud_rate: 9600 };
    pub const BUS_1: BusConfig = BusConfig { tx_gpio: 40, rx_gpio: 39, de_re_gpio: 41, baud_rate: 4800 };
}

pub mod sd_card {
    pub const DEVICE: &str = "spi2";
    pub const FS_TYPE: &str = "fat32";
    pub const DATA_LOG_PATH: &str = "/data.csv";
    pub const CS_GPIO: u32 = 10;
    pub const MOSI_GPIO: u32 = 11;
    pub const SCK_GPIO: u32 = 12;
    pub const MISO_GPIO: u32 = 13;
    pub const SPI_INIT_FREQUENCY_KHZ: u32 = 400;
    pub const DATA_CSV_FILE_NAME: &str = "data.csv";
    pub const DATA_CSV_HEADER: &str = "timestamp,temperature_celsius_0,humidity_percent_0,temperature_celsius_1,humidity_percent_1,temperature_celsius_2,humidity_percent_2,voltage_channel_0,voltage_channel_1,voltage_channel_2,voltage_channel_3";
    pub const FILE_UPLOAD_MAX_BYTES: usize = 4096;
}

pub mod ble {
    pub const CONNECTIONS_MAX: usize = 1;
    pub const L2CAP_CHANNELS_MAX: usize = 1;
}

pub mod data_logger {
    pub const SAMPLING_INTERVAL_SECS: u64 = 5;
    pub const POLL_RETRIES: usize = 40;
    pub const POLL_INTERVAL_MS: u64 = 250;
}

pub mod carbon_dioxide {
    pub const SCD4X_POLL_RETRIES: usize = 20;
    pub const SCD4X_POLL_INTERVAL_MS: u64 = 500;
    pub const PROBE_RETRY_SECS: u64 = 5;
    pub const MAX_CONSECUTIVE_FAILURES: usize = 5;
}

pub mod temperature_humidity {
    pub const I2C_ADDR: u8 = 0x44;
    pub const MAX_SENSORS: u8 = 8;
    pub const READ_DELAY_MS: u16 = 100;
}

pub mod voltage {
    pub const I2C_ADDR: u8 = 0x48;
    pub const CHANNEL_COUNT: u8 = 4;
}

pub mod eeprom {
    pub const I2C_ADDR: u8 = 0x50;
    pub const PAGE_SIZE: u16 = 32;
    pub const TOTAL_SIZE: u16 = 4096;
}

pub mod led {
    pub const GPIO: u8 = 38;
    pub const COUNT: u8 = 1;
    pub const BRIGHTNESS: u8 = 255;
}

pub mod shell {
    pub const BUF_IN: usize = 256;
    pub const BUF_OUT: usize = 256;
    pub const MAX_PATH_LEN: usize = 128;
}

pub mod telnet {
    pub const ENABLED: bool = false;
    pub const PORT: u16 = 23;
}

pub mod buttons {
    pub const GPIO_1: i8 = -1;
    pub const GPIO_2: i8 = 4;
    pub const GPIO_3: i8 = 42;
    pub const COUNT: u8 = 3;
    pub const DEBOUNCE_MS: u16 = 50;
    pub const LONG_PRESS_MS: u16 = 1000;
}

pub mod provisioning {
    pub const ENABLED: bool = false;
}

pub mod cloudevents {
    pub const TENANT: &str = "apidae-systems";
    pub const SITE: &str = "ottawa";
    pub const SOURCE: &str = "urn:apidae-systems:tenant:apidae-systems:site:ottawa";
    pub const EVENT_TYPE: &str = "com.apidae.system.device.status.v1";
}

pub mod smtp {
    pub const ENABLED: bool = false;
    pub const PORT: u16 = 587;
}

pub mod ws_shell {
    pub const RING_SIZE: u16 = 512;
    pub const WRITE_BUF: u16 = 1024;
}

// ─────────────────────────────────────────────────────────────────────────────
// Compile-time config validation
// ─────────────────────────────────────────────────────────────────────────────

const _: () = {
    assert!(i2c::BUS_0.sda_gpio != i2c::BUS_0.scl_gpio, "I2C bus 0: SDA and SCL must differ");
    assert!(i2c::BUS_1.sda_gpio != i2c::BUS_1.scl_gpio, "I2C bus 1: SDA and SCL must differ");
    assert!(ssh::PORT > 0, "Invalid SSH port");
    assert!(http::PORT > 0, "Invalid HTTP port");
    assert!(shell::BUF_IN >= 64, "Shell input buffer too small");
    assert!(shell::BUF_OUT >= 64, "Shell output buffer too small");
    assert!(buttons::COUNT <= 8, "Too many buttons");
};

// ─────────────────────────────────────────────────────────────────────────────
// Runtime configuration (flash-persisted WiFi credentials)
// ─────────────────────────────────────────────────────────────────────────────

pub mod runtime {
    //! Runtime configuration that may change after deployment.
    //!
    //! WiFi credentials are stored in a dedicated flash sector and survive
    //! firmware updates. The on-flash record is little-endian and uses a
    //! magic number to distinguish a written sector from an erased one.

    use embedded_storage::ReadStorage;
    use embedded_storage::nor_flash::NorFlash;
    use esp_storage::FlashStorage;

    pub const DEFAULT_SSID: &str = env!("NETWORK_WIFI_SSID");
    pub const DEFAULT_PASSWORD: &str = env!("NETWORK_WIFI_PSK");

    const CREDENTIALS_MAGIC: u32 = 0xCE6A0001;
    const CREDENTIALS_OFFSET: usize = 0x1000;
    #[allow(dead_code, reason = "used by credential update API endpoint")]
    const CREDENTIALS_SECTOR_SIZE: usize = 4096;
    const SSID_MAX_LEN: usize = 32;
    const PASSWORD_MAX_LEN: usize = 64;

    #[repr(C)]
    struct CredentialsRecord {
        magic: u32,
        ssid_len: u8,
        password_len: u8,
        ssid: [u8; SSID_MAX_LEN],
        password: [u8; PASSWORD_MAX_LEN],
    }

    pub struct WifiCredentials {
        pub ssid: heapless::String<SSID_MAX_LEN>,
        pub password: heapless::String<PASSWORD_MAX_LEN>,
    }

    pub fn read_credentials(flash: &mut FlashStorage) -> Option<WifiCredentials> {
        let mut buffer = [0u8; size_of::<CredentialsRecord>()];

        if flash.read(CREDENTIALS_OFFSET as u32, &mut buffer).is_err() {
            return None;
        }

        // SAFETY: `buffer` is exactly `size_of::<CredentialsRecord>()` bytes,
        // fully initialised by `flash.read`, and `CredentialsRecord` is
        // `#[repr(C)]` with a trivial bit pattern (no padding-sensitive
        // types). `read_unaligned` is used because the byte buffer is not
        // guaranteed to satisfy the struct's alignment.
        let record: CredentialsRecord =
            unsafe { core::ptr::read_unaligned(buffer.as_ptr() as *const _) };

        if record.magic != CREDENTIALS_MAGIC {
            return None;
        }

        let ssid_len = record.ssid_len as usize;
        let password_len = record.password_len as usize;

        if ssid_len > SSID_MAX_LEN || password_len > PASSWORD_MAX_LEN || ssid_len == 0 {
            return None;
        }

        let mut ssid = heapless::String::new();
        for &b in &record.ssid[..ssid_len] {
            if ssid.push(b as char).is_err() {
                break;
            }
        }

        let mut password = heapless::String::new();
        for &b in &record.password[..password_len] {
            if password.push(b as char).is_err() {
                break;
            }
        }

        Some(WifiCredentials { ssid, password })
    }

    pub fn write_credentials(flash: &mut FlashStorage, ssid: &str, password: &str) -> bool {
        if ssid.len() > SSID_MAX_LEN || password.len() > PASSWORD_MAX_LEN || ssid.is_empty() {
            return false;
        }

        let mut record = CredentialsRecord {
            magic: CREDENTIALS_MAGIC,
            ssid_len: ssid.len() as u8,
            password_len: password.len() as u8,
            ssid: [0u8; SSID_MAX_LEN],
            password: [0u8; PASSWORD_MAX_LEN],
        };

        record.ssid[..ssid.len()].copy_from_slice(ssid.as_bytes());
        record.password[..password.len()].copy_from_slice(password.as_bytes());

        let mut buffer = [0xFFu8; CREDENTIALS_SECTOR_SIZE];
        // SAFETY: `record` is a fully-initialised `#[repr(C)]` struct on the
        // stack, and we borrow it as a byte slice for the duration of the
        // copy below. The pointer is non-null, the length matches the struct
        // size exactly, and no mutation aliases this borrow.
        let record_bytes = unsafe {
            core::slice::from_raw_parts(
                &record as *const CredentialsRecord as *const u8,
                size_of::<CredentialsRecord>(),
            )
        };
        buffer[..record_bytes.len()].copy_from_slice(record_bytes);

        if NorFlash::erase(
            flash,
            CREDENTIALS_OFFSET as u32,
            (CREDENTIALS_OFFSET + CREDENTIALS_SECTOR_SIZE) as u32,
        )
        .is_err()
        {
            return false;
        }

        if flash.write(CREDENTIALS_OFFSET as u32, &buffer).is_err() {
            return false;
        }

        if let Some(verified) = read_credentials(flash) {
            verified.ssid.as_str() == ssid && verified.password.as_str() == password
        } else {
            false
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hardware topology
// ─────────────────────────────────────────────────────────────────────────────

pub mod topology {
    //! Hardware topology configuration.
    //!
    //! Migration path: load from NVS/flash JSON at runtime instead of static
    //! const.

    /// A metric that sensors can produce.
    pub struct MetricDef {
        pub name: &'static str,
        pub unit: &'static str,
    }

    /// Canonical metric registry.
    pub const METRICS: &[MetricDef] = &[
        MetricDef {
            name: "temperature",
            unit: "celsius",
        },
        MetricDef {
            name: "humidity",
            unit: "percent_relative_humidity",
        },
        MetricDef {
            name: "co2",
            unit: "ppm",
        },
        MetricDef {
            name: "wind_speed",
            unit: "metres_per_second",
        },
        MetricDef {
            name: "wind_direction",
            unit: "degrees",
        },
        MetricDef {
            name: "solar_radiation",
            unit: "watt_per_metre_squared",
        },
        MetricDef {
            name: "soil_moisture",
            unit: "percent",
        },
        MetricDef {
            name: "soil_temperature",
            unit: "celsius",
        },
        MetricDef {
            name: "soil_electrical_conductivity",
            unit: "microsiemens_per_cm",
        },
        MetricDef {
            name: "soil_salinity_raw",
            unit: "raw",
        },
        MetricDef {
            name: "soil_total_dissolved_solids",
            unit: "milligrams_per_litre",
        },
    ];

    /// Communication bus type.
    pub enum BusType {
        I2c,
        Rs485Modbus,
    }

    /// Configuration for a single communication bus.
    pub struct BusConfig {
        pub bus_type: BusType,
        pub bus_index: u8,
        pub label: &'static str,
        pub baud_rate: Option<u32>,
        pub sda_gpio: Option<u8>,
        pub scl_gpio: Option<u8>,
        pub tx_gpio: Option<u8>,
        pub rx_gpio: Option<u8>,
        pub de_re_gpio: Option<u8>,
    }

    impl BusConfig {
        pub fn is_i2c(&self) -> bool {
            matches!(self.bus_type, BusType::I2c)
        }

        pub fn is_rs485(&self) -> bool {
            matches!(self.bus_type, BusType::Rs485Modbus)
        }

        pub fn i2c_pins(&self) -> Option<(u8, u8)> {
            if self.is_i2c() {
                Some((self.sda_gpio?, self.scl_gpio?))
            } else {
                None
            }
        }
    }

    /// Sensor type discriminator.
    pub enum SensorKind {
        TemperatureAndHumidity,
        Scd30,
        Scd4x,
        Ds3231,
        WindSpeed,
        WindDirection,
        SolarRadiation,
        Soil,
        Ntc,
    }

    /// Configuration for a single sensor endpoint.
    pub struct SensorConfig {
        pub name: &'static str,
        pub kind: SensorKind,
        pub model: &'static str,
        pub bus_label: &'static str,
        pub i2c_address: Option<u8>,
        pub modbus_slave_id: Option<u8>,
        /// I2C multiplexer channel. `None` means no multiplexer (direct connection).
        pub mux_channel: Option<u8>,
        pub is_enabled: bool,
        /// Metric names this sensor produces (references `METRICS` by name).
        pub metric_names: &'static [&'static str],
    }

    impl SensorConfig {
        pub fn is_i2c(&self) -> bool {
            self.i2c_address.is_some()
        }

        pub fn is_modbus(&self) -> bool {
            self.modbus_slave_id.is_some()
        }

        pub fn uses_mux(&self) -> bool {
            self.mux_channel.is_some()
        }
    }

    /// Complete hardware topology for the current board.
    pub struct HardwareTopology {
        pub buses: &'static [BusConfig],
        pub sensors: &'static [SensorConfig],
    }

    impl HardwareTopology {
        /// Find a bus by its label.
        pub fn find_bus(&self, label: &str) -> Option<&BusConfig> {
            self.buses.iter().find(|b| b.label == label)
        }

        /// Iterate over enabled sensors.
        pub fn enabled_sensors(&self) -> impl Iterator<Item = &SensorConfig> {
            self.sensors.iter().filter(|s| s.is_enabled)
        }

        /// Iterate over enabled sensors of a specific kind.
        pub fn enabled_sensors_of_kind(
            &self,
            kind: SensorKind,
        ) -> impl Iterator<Item = &SensorConfig> {
            self.sensors
                .iter()
                .filter(move |s| s.is_enabled && matches!((&s.kind, &kind), (a, b) if core::mem::discriminant(a) == core::mem::discriminant(b)))
        }

        /// Find the first enabled sensor of a specific kind.
        pub fn first_enabled_sensor_of_kind(&self, kind: SensorKind) -> Option<&SensorConfig> {
            self.enabled_sensors_of_kind(kind).next()
        }

        /// Find the first sensor of a specific kind, regardless of whether
        /// it is currently enabled. Use this when you need the sensor's
        /// declared address or bus label (e.g. in tests that probe the
        /// physical device) without requiring the production sensor task
        /// to be spawned at boot.
        pub fn find_sensor_of_kind(&self, kind: SensorKind) -> Option<&SensorConfig> {
            self.sensors.iter().find(move |sensor_configuration| {
                core::mem::discriminant(&sensor_configuration.kind)
                    == core::mem::discriminant(&kind)
            })
        }
    }

    /// Hardware topology for the current ESP32-S3 board.
    ///
    /// To change hardware configuration:
    /// 1. Add/remove buses in `buses`
    /// 2. Add/remove sensors in `sensors`
    /// 3. Set `enabled: false` to temporarily disable a sensor
    /// 4. Set `mux_channel: None` to skip I2C multiplexer selection
    pub const CURRENT_TOPOLOGY: HardwareTopology = HardwareTopology {
        buses: &[
            BusConfig {
                bus_type: BusType::I2c,
                bus_index: 0,
                label: "i2c.0",
                baud_rate: None,
                sda_gpio: Some(8),
                scl_gpio: Some(9),
                tx_gpio: None,
                rx_gpio: None,
                de_re_gpio: None,
            },
            BusConfig {
                bus_type: BusType::I2c,
                bus_index: 1,
                label: "i2c.1",
                baud_rate: None,
                sda_gpio: Some(17),
                scl_gpio: Some(18),
                tx_gpio: None,
                rx_gpio: None,
                de_re_gpio: None,
            },
        ],
        sensors: &[
            SensorConfig {
                name: "temperature_and_humidity_0",
                kind: SensorKind::TemperatureAndHumidity,
                model: "SHT31",
                bus_label: "i2c.0",
                i2c_address: Some(0x44),
                modbus_slave_id: None,
                mux_channel: None,
                is_enabled: true,
                metric_names: &["temperature", "humidity"],
            },
            SensorConfig {
                name: "scd30_0",
                kind: SensorKind::Scd30,
                model: "SCD30",
                bus_label: "i2c.1",
                i2c_address: Some(0x61),
                modbus_slave_id: None,
                mux_channel: None,
                is_enabled: false,
                metric_names: &["co2", "temperature", "humidity"],
            },
            // Declared for test discovery only — `is_enabled: false` keeps
            // the production sensor loop from touching them until the
            // I2C scanner confirms their physical wiring. Flip to `true`
            // (and correct `bus_label` if needed) once the board wiring
            // is final.
            SensorConfig {
                name: "scd4x_0",
                kind: SensorKind::Scd4x,
                model: "SCD4x",
                bus_label: "i2c.1",
                i2c_address: Some(0x62),
                modbus_slave_id: None,
                mux_channel: None,
                is_enabled: false,
                metric_names: &["co2", "temperature", "humidity"],
            },
            SensorConfig {
                name: "ds3231_0",
                kind: SensorKind::Ds3231,
                model: "DS3231",
                bus_label: "i2c.1",
                i2c_address: Some(0x68),
                modbus_slave_id: None,
                mux_channel: None,
                is_enabled: true,
                metric_names: &[],
            },
        ],
    };
}
