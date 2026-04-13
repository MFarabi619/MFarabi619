use crate::api::{Co2ConfigData, Co2ConfigResponse};
use reqwest::Error;

pub struct Co2Service;

impl Co2Service {
    pub async fn get_config(base_url: &str) -> Result<Co2ConfigResponse, Error> {
        reqwest::get(format!("{base_url}/api/co2/config"))
            .await?
            .json()
            .await
    }

    pub async fn set_config(
        base_url: &str,
        config: &serde_json::Value,
    ) -> Result<serde_json::Value, Error> {
        reqwest::Client::new()
            .post(format!("{base_url}/api/co2/config"))
            .json(config)
            .send()
            .await?
            .json()
            .await
    }

    pub async fn start(base_url: &str) -> Result<serde_json::Value, Error> {
        reqwest::Client::new()
            .post(format!("{base_url}/api/co2/start"))
            .send()
            .await?
            .json()
            .await
    }

    pub async fn stop(base_url: &str) -> Result<serde_json::Value, Error> {
        reqwest::Client::new()
            .post(format!("{base_url}/api/co2/stop"))
            .send()
            .await?
            .json()
            .await
    }
}