use crate::api::DeviceStatusEnvelope;
use reqwest::Error;

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
}