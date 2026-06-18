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
    pub sleep: DeviceSleep,
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
    #[serde(default)]
    pub temperature_celsius: f64,
    pub memory_heap_free: u64,
    #[serde(default)]
    pub memory_heap_total: u64,
    #[serde(default)]
    pub memory_heap_min_free: u64,
    #[serde(default)]
    pub memory_heap_max_alloc: u64,
    #[serde(default)]
    pub memory_psram_total: u64,
    #[serde(default)]
    pub memory_psram_free: u64,
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

#[derive(Debug, Clone, Deserialize)]
pub struct DeviceSleep {
    #[serde(default)]
    pub pending: bool,
    #[serde(default)]
    pub requested_duration_seconds: u64,
    #[serde(default)]
    pub wake_cause: String,
    #[serde(default)]
    pub timer_wakeup_enabled: bool,
    #[serde(default)]
    pub timer_wakeup_us: u64,
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub default_duration_seconds: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SleepConfigResponse {
    pub ok: bool,
    pub data: SleepConfigData,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct SleepConfigData {
    pub enabled: bool,
    pub duration_seconds: u64,
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

pub fn format_storage_pair(used: u64, total: u64) -> String {
    let (used_val, total_val, unit) = if total < 1024 {
        (used as f64, total as f64, "B")
    } else if total < 1024 * 1024 {
        (used as f64 / 1024.0, total as f64 / 1024.0, "KB")
    } else {
        (
            used as f64 / (1024.0 * 1024.0),
            total as f64 / (1024.0 * 1024.0),
            "MB",
        )
    };
    format!("{used_val:.1} / {total_val:.1} {unit}")
}
