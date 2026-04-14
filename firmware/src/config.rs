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
    pub const BUS_0: BusConfig = BusConfig {
        sda_gpio: 8,
        scl_gpio: 9,
    };
    pub const BUS_1: BusConfig = BusConfig {
        sda_gpio: 17,
        scl_gpio: 18,
    };
    pub const MUX_ADDR: u8 = 0x70;
    pub const DIRECT_CHANNEL: i8 = -1;
    pub const ANY_MUX_CHANNEL: i8 = -2;
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum I2CSensorKind {
    TemperatureHumidity,
    CarbonDioxideScd30,
    CarbonDioxideScd4x,
    RtcDs3231,
}

#[derive(Clone, Copy)]
pub struct I2CSensorConfig {
    pub name: &'static str,
    pub model: &'static str,
    pub kind: I2CSensorKind,
    pub bus_index: u8,
    pub address: u8,
    pub mux_channel: i8,
}

pub mod i2c_topology {
    use super::{I2CSensorConfig, I2CSensorKind};

    // Sensors are intentionally disabled for now while the Rust transport and
    // ownership model catches up with the cleaner C++ architecture. Keep the
    // prior topology entries here as commented reference so they can be
    // reintroduced deliberately instead of rediscovered from git history.
    pub const DEVICES: &[I2CSensorConfig] = &[
        // I2CSensorConfig {
        //     name: "temperature_and_humidity_0",
        //     model: "SHT31",
        //     kind: I2CSensorKind::TemperatureHumidity,
        //     bus_index: 0,
        //     address: 0x44,
        //     mux_channel: super::i2c::DIRECT_CHANNEL,
        // },
        // I2CSensorConfig {
        //     name: "scd30_0",
        //     model: "SCD30",
        //     kind: I2CSensorKind::CarbonDioxideScd30,
        //     bus_index: 1,
        //     address: 0x61,
        //     mux_channel: super::i2c::DIRECT_CHANNEL,
        // },
        // I2CSensorConfig {
        //     name: "scd4x_0",
        //     model: "SCD4x",
        //     kind: I2CSensorKind::CarbonDioxideScd4x,
        //     bus_index: 1,
        //     address: 0x62,
        //     mux_channel: super::i2c::DIRECT_CHANNEL,
        // },
        // I2CSensorConfig {
        //     name: "ds3231_0",
        //     model: "DS3231",
        //     kind: I2CSensorKind::RtcDs3231,
        //     bus_index: 1,
        //     address: 0x68,
        //     mux_channel: super::i2c::DIRECT_CHANNEL,
        // },
    ];

    pub fn devices_of_kind(kind: I2CSensorKind) -> impl Iterator<Item = &'static I2CSensorConfig> {
        DEVICES.iter().filter(move |device| device.kind == kind)
    }

    pub fn first_device_of_kind(kind: I2CSensorKind) -> Option<&'static I2CSensorConfig> {
        devices_of_kind(kind).next()
    }
}

pub mod rs485 {
    pub struct BusConfig {
        pub tx_gpio: i8,
        pub rx_gpio: i8,
        pub de_re_gpio: i8,
        pub baud_rate: u32,
    }
    pub const BUS_0: BusConfig = BusConfig {
        tx_gpio: 45,
        rx_gpio: 48,
        de_re_gpio: 47,
        baud_rate: 9600,
    };
    pub const BUS_1: BusConfig = BusConfig {
        tx_gpio: 40,
        rx_gpio: 39,
        de_re_gpio: 41,
        baud_rate: 4800,
    };
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum ModbusSensorKind {
    WindSpeed,
    WindDirection,
    SolarRadiation,
    Soil,
}

#[derive(Clone, Copy)]
pub struct ModbusSensorConfig {
    pub name: &'static str,
    pub model: &'static str,
    pub kind: ModbusSensorKind,
    pub channel: u8,
    pub slave_id: u8,
    pub register_address: u16,
}

pub mod modbus_topology {
    use super::{ModbusSensorConfig, ModbusSensorKind};

    pub const DEVICES: &[ModbusSensorConfig] = &[
        // ModbusSensorConfig {
        //     name: "wind_speed_0",
        //     model: "DFRobot SEN0483",
        //     kind: ModbusSensorKind::WindSpeed,
        //     channel: 0,
        //     slave_id: 20,
        //     register_address: 0,
        // },
        // ModbusSensorConfig {
        //     name: "wind_direction_0",
        //     model: "DFRobot SEN0482",
        //     kind: ModbusSensorKind::WindDirection,
        //     channel: 0,
        //     slave_id: 30,
        //     register_address: 0,
        // },
        // ModbusSensorConfig {
        //     name: "solar_radiation_0",
        //     model: "DFRobot SEN0640",
        //     kind: ModbusSensorKind::SolarRadiation,
        //     channel: 0,
        //     slave_id: 40,
        //     register_address: 0,
        // },
    ];

    pub fn devices_of_kind(
        kind: ModbusSensorKind,
    ) -> impl Iterator<Item = &'static ModbusSensorConfig> {
        DEVICES.iter().filter(move |device| device.kind == kind)
    }

    pub fn first_device_of_kind(kind: ModbusSensorKind) -> Option<&'static ModbusSensorConfig> {
        devices_of_kind(kind).next()
    }
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
    assert!(
        i2c::BUS_0.sda_gpio != i2c::BUS_0.scl_gpio,
        "I2C bus 0: SDA and SCL must differ"
    );
    assert!(
        i2c::BUS_1.sda_gpio != i2c::BUS_1.scl_gpio,
        "I2C bus 1: SDA and SCL must differ"
    );
    assert!(ssh::PORT > 0, "Invalid SSH port");
    assert!(http::PORT > 0, "Invalid HTTP port");
    assert!(shell::BUF_IN >= 64, "Shell input buffer too small");
    assert!(shell::BUF_OUT >= 64, "Shell output buffer too small");
    assert!(buttons::COUNT <= 8, "Too many buttons");
};

// ─────────────────────────────────────────────────────────────────────────────
// Runtime configuration (flash-persisted WiFi credentials)
// ─────────────────────────────────────────────────────────────────────────────
