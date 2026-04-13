use heapless::String as HeaplessString;
use serde::{Deserialize, Serialize};

// ─── Client → Device ────────────────────────────────────────────────────────
//
// serde_json_core doesn't support internally tagged enums, so we parse
// the "action" field manually and deserialize the payload separately.

#[derive(Deserialize)]
pub struct RawRequest<'a> {
    pub action: &'a str,
    #[serde(default)]
    pub ssid: Option<&'a str>,
    #[serde(default)]
    pub password: Option<&'a str>,
    #[serde(default)]
    pub location: Option<&'a str>,
    #[serde(default)]
    pub path: Option<&'a str>,
}

pub enum DeviceRequest<'a> {
    GetStatus,
    GetCo2,
    ScanWifi,
    ConnectWifi { ssid: &'a str, password: &'a str },
    ListFiles { location: &'a str },
    DeleteFile { location: &'a str, path: &'a str },
    Unknown,
}

impl<'a> From<RawRequest<'a>> for DeviceRequest<'a> {
    fn from(raw: RawRequest<'a>) -> Self {
        match raw.action {
            "get_status" => DeviceRequest::GetStatus,
            "get_co2" => DeviceRequest::GetCo2,
            "scan_wifi" => DeviceRequest::ScanWifi,
            "connect_wifi" => DeviceRequest::ConnectWifi {
                ssid: raw.ssid.unwrap_or(""),
                password: raw.password.unwrap_or(""),
            },
            "list_files" => DeviceRequest::ListFiles {
                location: raw.location.unwrap_or("sd"),
            },
            "delete_file" => DeviceRequest::DeleteFile {
                location: raw.location.unwrap_or("sd"),
                path: raw.path.unwrap_or(""),
            },
            _ => DeviceRequest::Unknown,
        }
    }
}

// ─── Device → Client ────────────────────────────────────────────────────────

#[derive(Serialize)]
#[serde(tag = "type")]
pub enum DeviceEvent<'a> {
    #[serde(rename = "status")]
    Status {
        hostname: &'a str,
        platform: &'a str,
        uptime_seconds: u64,
        heap_free: usize,
        heap_used: usize,
        sd_card_mb: u32,
    },
    #[serde(rename = "co2")]
    Co2 {
        co2_ppm: f32,
        temperature: f32,
        humidity: f32,
        model: &'a str,
        ok: bool,
    },
    #[serde(rename = "wifi_scan")]
    WifiScan {
        networks: &'a [WifiNetworkEntry],
    },
    #[serde(rename = "wifi_status")]
    WifiStatus {
        connected: bool,
        ssid: &'a str,
        ipv4: HeaplessString<16>,
        rssi: i32,
    },
    #[serde(rename = "file_list")]
    FileList {
        location: &'a str,
        files: &'a [FileEntryPayload],
    },
    #[serde(rename = "error")]
    Error {
        message: &'a str,
    },
}

#[derive(Serialize)]
pub struct WifiNetworkEntry {
    pub ssid: HeaplessString<32>,
    pub rssi: i8,
    pub channel: u8,
}

#[derive(Serialize)]
pub struct FileEntryPayload {
    pub name: HeaplessString<32>,
    pub size: u32,
}
