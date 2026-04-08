pub mod sntp;
pub mod tcp;
pub mod wifi;

pub fn build_sta_config(credentials: &crate::config::runtime::WifiCredentials) -> esp_radio::wifi::Config {
    esp_radio::wifi::Config::Station(
        esp_radio::wifi::sta::StationConfig::default()
            .with_ssid(credentials.ssid.as_str())
            .with_password(credentials.password.as_str().into()),
    )
}
