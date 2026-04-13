use crate::api::{WifiScanResponse, WifiNetwork, WirelessStatusResponse};
use reqwest::Error;

pub struct WifiService;

impl WifiService {
    pub async fn get_status(base_url: &str) -> Result<WirelessStatusResponse, Error> {
        reqwest::get(format!("{base_url}/api/wireless/status"))
            .await?
            .json()
            .await
    }

    pub async fn scan(base_url: &str) -> Result<WifiScanResponse, Error> {
        reqwest::Client::new()
            .post(format!("{base_url}/api/wireless/actions/scan"))
            .send()
            .await?
            .json()
            .await
    }

    pub async fn connect(base_url: &str, ssid: &str, password: &str) -> Result<serde_json::Value, Error> {
        reqwest::Client::new()
            .post(format!("{base_url}/api/wireless/actions/connect"))
            .json(&serde_json::json!({ "ssid": ssid, "password": password }))
            .send()
            .await?
            .json()
            .await
    }
}