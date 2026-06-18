use serde::Deserialize;
use reqwest::Error;

#[derive(Clone, Debug, Default, Deserialize)]
pub struct SensorInventory {
    pub temperature_humidity_count: u8,
    pub soil_probe_count: u8,
    pub voltage_available: bool,
    pub current_available: bool,
    pub co2_available: bool,
    pub wind_speed_available: bool,
    pub wind_direction_available: bool,
    pub solar_radiation_available: bool,
    pub barometric_pressure_available: bool,
    pub rainfall_available: bool,
}

#[derive(Clone, Debug, Deserialize)]
pub struct SensorInventoryResponse {
    pub ok: bool,
    pub data: SensorInventory,
}

pub struct SensorsService;

impl SensorsService {
    pub async fn inventory(url: &str) -> Result<SensorInventoryResponse, Error> {
        reqwest::get(format!("{url}/api/sensors/inventory"))
            .await?
            .json()
            .await
    }
}