use defmt::info;
use esp_storage::FlashStorage;

use crate::config;

pub mod credentials;
pub mod sta;

pub struct AccessPointSnapshot {
    pub fallback_enabled: bool,
    pub ssid: &'static str,
    pub channel: u8,
    pub max_connections: u8,
    pub auth_mode: &'static str,
}

pub struct WifiSnapshot {
    pub station: sta::StaSnapshot,
    pub access_point: AccessPointSnapshot,
}

pub fn snapshot() -> WifiSnapshot {
    WifiSnapshot {
        station: sta::snapshot(),
        access_point: AccessPointSnapshot {
            fallback_enabled: config::wifi::FALLBACK_TO_AP,
            ssid: config::wifi::ap::SSID,
            channel: config::wifi::ap::CHANNEL,
            max_connections: config::wifi::ap::MAX_CONNECTIONS,
            auth_mode: config::wifi::ap::AUTH_MODE,
        },
    }
}

pub fn station_config(credentials: &credentials::WifiCredentials) -> esp_radio::wifi::Config {
    esp_radio::wifi::Config::Station(
        esp_radio::wifi::sta::StationConfig::default()
            .with_ssid(credentials.ssid.as_str())
            .with_password(credentials.password.as_str().into()),
    )
}

pub fn load_credentials_or_default(
    flash: &mut FlashStorage,
) -> credentials::WifiCredentials {
    credentials::read_from_flash(flash).unwrap_or_else(|| {
        info!("no credentials in flash, using defaults");
        credentials::default_credentials()
    })
}
