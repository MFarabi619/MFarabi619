pub mod sntp;
pub mod tcp;
pub mod wifi;

#[derive(Clone, Copy)]
pub struct WifiStationConfig {
    pub connect_timeout_seconds: u64,
    pub retry_interval_seconds: u64,
}

#[derive(Clone, Copy)]
pub struct WifiAccessPointConfig {
    pub ssid: &'static str,
    pub password: &'static str,
    pub channel: u8,
    pub max_connections: u8,
    pub auth_mode: &'static str,
}

#[derive(Clone, Copy)]
pub struct NetworkingConfig {
    pub ntp_server: &'static str,
    pub station: WifiStationConfig,
    pub access_point: WifiAccessPointConfig,
    pub fallback_to_access_point: bool,
}

pub const NETWORKING: NetworkingConfig = NetworkingConfig {
    ntp_server: crate::config::NTP_SERVER,
    station: WifiStationConfig {
        connect_timeout_seconds: crate::config::wifi::CONNECT_TIMEOUT_SECS,
        retry_interval_seconds: crate::config::wifi::RETRY_INTERVAL_SECS,
    },
    access_point: WifiAccessPointConfig {
        ssid: crate::config::wifi::ap::SSID,
        password: crate::config::wifi::ap::PASSWORD,
        channel: crate::config::wifi::ap::CHANNEL,
        max_connections: crate::config::wifi::ap::MAX_CONNECTIONS,
        auth_mode: crate::config::wifi::ap::AUTH_MODE,
    },
    fallback_to_access_point: crate::config::wifi::FALLBACK_TO_AP,
};

pub fn build_sta_config(credentials: &crate::config::runtime::WifiCredentials) -> esp_radio::wifi::Config {
    esp_radio::wifi::Config::Station(
        esp_radio::wifi::sta::StationConfig::default()
            .with_ssid(credentials.ssid.as_str())
            .with_password(credentials.password.as_str().into()),
    )
}
