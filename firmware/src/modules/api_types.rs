use heapless::{String as HeaplessString, Vec as HeaplessVec};
use picoserve::response::Json;
use serde::Serialize;

#[derive(Serialize)]
pub struct ApiErrorPayload<'a> {
    pub code: &'a str,
    pub message: &'a str,
}

#[derive(Serialize)]
pub struct ApiErrorEnvelope<'a> {
    pub ok: bool,
    pub error: ApiErrorPayload<'a>,
}

#[derive(Serialize)]
pub struct ApiSuccessEnvelope<T: Serialize> {
    pub ok: bool,
    pub data: T,
}

#[derive(Serialize)]
pub struct FilesystemEntryPayload {
    pub name: HeaplessString<32>,
    pub size: u32,
    pub last_write_unix: u64,
}

#[derive(Serialize)]
pub struct FilesystemListPayload {
    pub entries: HeaplessVec<FilesystemEntryPayload, 64>,
}

#[derive(Serialize)]
pub struct FileUploadPayload {
    pub name: HeaplessString<32>,
    pub size: usize,
}

#[derive(Serialize)]
pub struct SystemDeviceStatusCloudEvent<'a> {
    pub specversion: &'a str,
    pub id: HeaplessString<48>,
    pub source: &'a str,
    #[serde(rename = "type")]
    pub event_type: &'a str,
    pub datacontenttype: &'a str,
    pub time: &'a str,
    pub data: SystemDeviceStatusData<'a>,
}

#[derive(Serialize)]
pub struct SystemDeviceStatusData<'a> {
    pub device: SystemDeviceStatusDeviceData<'a>,
    pub network: SystemDeviceStatusNetworkData<'a>,
    pub runtime: SystemDeviceStatusRuntimeData,
    pub storage: SystemDeviceStatusStorageData<'a>,
}

#[derive(Serialize)]
pub struct SystemDeviceStatusDeviceData<'a> {
    pub chip_id: u32,
    pub chip_model: &'a str,
    pub chip_cores: u8,
    pub chip_revision: u8,
    pub efuse_mac: &'a str,
}

#[derive(Serialize)]
pub struct SystemDeviceStatusNetworkData<'a> {
    pub ipv4_address: &'a str,
    pub wifi_rssi: i32,
}

#[derive(Serialize)]
pub struct SystemDeviceStatusRuntimeData {
    pub uptime: HeaplessString<24>,
    pub uptime_seconds: u64,
    pub memory_heap_bytes: usize,
}

#[derive(Serialize)]
pub struct SystemDeviceStatusStorageData<'a> {
    pub location: &'a str,
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub free_bytes: u64,
}

pub fn build_json_error_response<'a>(
    error_code: &'a str,
    error_message: &'a str,
) -> Json<ApiErrorEnvelope<'a>> {
    Json(ApiErrorEnvelope {
        ok: false,
        error: ApiErrorPayload {
            code: error_code,
            message: error_message,
        },
    })
}
