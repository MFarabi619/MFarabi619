use crate::api::{DeviceStatusEnvelope, SleepConfigResponse};
use reqwest::Error;
use serde_json::json;

pub struct DeviceService;

impl DeviceService {
    pub async fn get_status(base_url: &str) -> Result<DeviceStatusEnvelope, Error> {
        reqwest::get(format!("{base_url}/api/system/device/status"))
            .await?
            .json()
            .await
    }

    pub async fn get_status_for_location(base_url: &str, location: &str) -> Result<DeviceStatusEnvelope, Error> {
        let location = urlencoding::encode(location);
        reqwest::get(format!("{base_url}/api/system/device/status?location={location}"))
            .await?
            .json()
            .await
    }

    pub async fn update_sleep_config(
        base_url: &str,
        enabled: bool,
        duration_seconds: u64,
    ) -> Result<SleepConfigResponse, Error> {
        reqwest::Client::new()
            .post(format!("{base_url}/api/system/sleep/config"))
            .json(&json!({
                "enabled": enabled,
                "duration_seconds": duration_seconds,
            }))
            .send()
            .await?
            .json()
            .await
    }

    pub async fn trigger_sleep(base_url: &str) -> Result<SleepConfigResponse, Error> {
        reqwest::Client::new()
            .post(format!("{base_url}/api/system/sleep/actions/trigger"))
            .send()
            .await?
            .json()
            .await
    }
}
