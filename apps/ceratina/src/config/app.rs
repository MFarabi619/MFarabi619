//! Application configuration — changes per deployment.
//!
//! Ports, timeouts, buffer sizes, polling intervals,
//! credentials, service tuning.

pub const HOSTNAME: &str = {
    let h = option_env!("HOSTNAME");
    match h {
        Some(v) if !v.is_empty() => v,
        _ => "microvisor",
    }
};

pub const SSH_USER: &str = {
    let shell_user = option_env!("SHELL_USER");
    match shell_user {
        Some(u) if !u.is_empty() => u,
        _ => env!("USER"),
    }
};

pub const SSH_HOST_KEY_FILE: &str = ".SSH/HOST_KEY";
pub const NTP_SERVER: &str = "pool.ntp.org";
pub const ACTIVE_USER_KEY: &str = cloudevents::TENANT;

pub mod sntp {
    pub const MAX_ATTEMPTS: usize = 3;
    pub const RETRY_INTERVAL_SECS: u64 = 60;
    pub const ATTEMPT_INTERVAL_SECS: u64 = 5;
}

pub mod time {
    pub const ZONE: &str = "America/Toronto";
    pub const UTC_OFFSET_HOURS: i64 = -4;
}

pub mod wifi {
    pub const CONNECT_TIMEOUT_SECS: u64 = 15;
    pub const RETRY_INTERVAL_SECS: u64 = 5;
    pub const FALLBACK_TO_AP: bool = true;

    pub mod ap {
        pub const SSID: &str = "ceratina-access-point";
        pub const PASSWORD: &str = "ceratina";
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

pub mod sd_card {
    pub const DEVICE: &str = "spi2";
    pub const FS_TYPE: &str = "fat32";
    pub const DATA_LOG_PATH: &str = "/data.csv";
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
    pub const MAX_SENSORS: u8 = 8;
    pub const READ_DELAY_MS: u16 = 100;
}

pub mod voltage {
    pub const CHANNEL_COUNT: u8 = 4;
}

pub mod led {
    pub const BRIGHTNESS: u8 = 255;
}

pub mod shell {
    pub const BUF_IN: usize = 256;
    pub const BUF_OUT: usize = 256;
    pub const MAX_PATH_LEN: usize = 128;
}

pub mod buttons {
    pub const DEBOUNCE_MS: u16 = 50;
    pub const LONG_PRESS_MS: u16 = 1000;
}

pub mod cloudevents {
    pub const TENANT: &str = "apidae-systems";
    pub const SITE: &str = "ottawa";
    pub const SOURCE: &str = "urn:apidae-systems:tenant:apidae-systems:site:ottawa";
    pub const EVENT_TYPE: &str = "com.apidae.system.device.status.v1";
}

pub mod smtp {
    pub const PORT: u16 = 587;
}

pub mod ws_shell {
    pub const RING_SIZE: u16 = 512;
    pub const WRITE_BUF: u16 = 1024;
}

pub mod telnet {
    pub const PORT: u16 = 23;
}
