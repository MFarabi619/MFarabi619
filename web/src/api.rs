use serde::{Deserialize, Serialize};

pub const DEFAULT_DEVICE_URL: &str = "http://ceratina.local";

// ─── /api/system/device/status ──────────────────────────────────────────────

#[derive(Debug, Clone, Deserialize)]
pub struct DeviceStatusEnvelope {
    pub data: DeviceStatusData,
    pub time: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DeviceStatusData {
    pub device: DeviceIdentity,
    pub network: DeviceNetwork,
    pub runtime: DeviceRuntime,
    pub storage: DeviceStorage,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DeviceIdentity {
    pub chip_model: String,
    pub chip_cores: u32,
    pub chip_revision: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DeviceNetwork {
    pub ipv4_address: String,
    pub wifi_rssi: i32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DeviceRuntime {
    pub uptime: String,
    pub uptime_seconds: u64,
    pub memory_heap_bytes: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DeviceStorage {
    pub location: String,
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub free_bytes: u64,
}

impl DeviceStorage {
    pub fn percent_used(&self) -> f64 {
        if self.total_bytes == 0 {
            0.0
        } else {
            (self.used_bytes as f64 / self.total_bytes as f64) * 100.0
        }
    }
}

// ─── /api/cloudevents ───────────────────────────────────────────────────────

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CloudEvent {
    pub id: String,
    #[serde(rename = "type")]
    pub event_type: String,
    pub time: String,
    pub data: serde_json::Value,
}

// ─── /api/wireless/status ───────────────────────────────────────────────────

#[derive(Debug, Clone, Deserialize)]
pub struct WirelessStatusResponse {
    pub ok: bool,
    pub data: WirelessStatusData,
}

#[derive(Debug, Clone, Deserialize)]
pub struct WirelessStatusData {
    pub connected: bool,
    pub sta_ssid: String,
    pub sta_ipv4: String,
    pub wifi_rssi: i32,
    pub ap_active: bool,
    pub ap_ssid: String,
    pub ap_ipv4: String,
}

// ─── /api/wireless/actions/scan ─────────────────────────────────────────────

#[derive(Debug, Clone, Deserialize)]
pub struct WifiScanResponse {
    pub ok: bool,
    pub data: WifiScanData,
}

#[derive(Debug, Clone, Deserialize)]
pub struct WifiScanData {
    pub scan_count: u32,
    pub networks: Vec<WifiNetwork>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct WifiNetwork {
    pub ssid: String,
    pub rssi: i32,
    pub channel: u8,
    pub encryption: String,
    pub open: bool,
}

// ─── /api/filesystem/list ───────────────────────────────────────────────────

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct FileEntry {
    pub name: String,
    pub size: u64,
}

// ─── Fetch helpers ──────────────────────────────────────────────────────────

pub async fn fetch_device_status(base_url: &str) -> Result<DeviceStatusEnvelope, reqwest::Error> {
    reqwest::get(format!("{base_url}/api/system/device/status"))
        .await?
        .json()
        .await
}

pub async fn fetch_device_status_for_location(base_url: &str, location: &str) -> Result<DeviceStatusEnvelope, reqwest::Error> {
    let location = urlencoding::encode(location);
    reqwest::get(format!("{base_url}/api/system/device/status?location={location}"))
        .await?
        .json()
        .await
}

pub async fn fetch_cloudevents(base_url: &str) -> Result<Vec<CloudEvent>, reqwest::Error> {
    reqwest::get(format!("{base_url}/api/cloudevents"))
        .await?
        .json()
        .await
}

pub async fn fetch_wireless_status(base_url: &str) -> Result<WirelessStatusResponse, reqwest::Error> {
    reqwest::get(format!("{base_url}/api/wireless/status"))
        .await?
        .json()
        .await
}

pub async fn fetch_wifi_scan(base_url: &str) -> Result<WifiScanResponse, reqwest::Error> {
    reqwest::Client::new()
        .post(format!("{base_url}/api/wireless/actions/scan"))
        .send()
        .await?
        .json()
        .await
}

pub async fn fetch_filesystem(base_url: &str, location: &str) -> Result<Vec<FileEntry>, reqwest::Error> {
    let location = urlencoding::encode(location);
    reqwest::get(format!("{base_url}/api/filesystem/list?location={location}"))
        .await?
        .json()
        .await
}

pub async fn connect_wifi(base_url: &str, ssid: &str, password: &str) -> Result<serde_json::Value, reqwest::Error> {
    reqwest::Client::new()
        .post(format!("{base_url}/api/wireless/actions/connect"))
        .json(&serde_json::json!({ "ssid": ssid, "password": password }))
        .send()
        .await?
        .json()
        .await
}

pub async fn delete_file(base_url: &str, location: &str, path: &str) -> Result<reqwest::Response, reqwest::Error> {
    let location = urlencoding::encode(location);
    let path = urlencoding::encode(path);
    reqwest::Client::new()
        .delete(format!("{base_url}/api/filesystem/delete?location={location}&path={path}"))
        .send()
        .await
}

// ─── CO2 control ────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Deserialize)]
pub struct Co2ConfigResponse {
    pub ok: bool,
    pub data: Co2ConfigData,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Co2ConfigData {
    pub model: String,
    pub measuring: bool,
    pub measurement_interval_seconds: u16,
    pub auto_calibration_enabled: bool,
    pub temperature_offset_celsius: f64,
    pub altitude_meters: u16,
}

pub async fn fetch_co2_config(base_url: &str) -> Result<Co2ConfigResponse, reqwest::Error> {
    reqwest::get(format!("{base_url}/api/co2/config"))
        .await?
        .json()
        .await
}

pub async fn set_co2_config(base_url: &str, config: &serde_json::Value) -> Result<serde_json::Value, reqwest::Error> {
    reqwest::Client::new()
        .post(format!("{base_url}/api/co2/config"))
        .json(config)
        .send()
        .await?
        .json()
        .await
}

pub async fn start_co2(base_url: &str) -> Result<serde_json::Value, reqwest::Error> {
    reqwest::Client::new()
        .post(format!("{base_url}/api/co2/start"))
        .send()
        .await?
        .json()
        .await
}

pub async fn stop_co2(base_url: &str) -> Result<serde_json::Value, reqwest::Error> {
    reqwest::Client::new()
        .post(format!("{base_url}/api/co2/stop"))
        .send()
        .await?
        .json()
        .await
}

// ─── Utilities ──────────────────────────────────────────────────────────────

pub fn format_file_size(bytes: u64) -> String {
    if bytes < 1024 {
        format!("{} B", bytes)
    } else if bytes < 1024 * 1024 {
        format!("{:.1} KB", bytes as f64 / 1024.0)
    } else {
        format!("{:.1} MB", bytes as f64 / (1024.0 * 1024.0))
    }
}
