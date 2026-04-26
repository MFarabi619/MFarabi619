use heapless::String as HeaplessString;
use picoserve::response::{IntoResponse, Json};
use serde::Serialize;

use crate::sensors::manager;
use crate::services::system;

#[derive(Serialize)]
struct ApiResponse<'a> {
    co2: Co2Data,
    status: StatusData<'a>,
    sensors: heapless::Vec<SensorData<'a>, { manager::MAX_SENSOR_COUNT }>,
    files: heapless::Vec<FileData, 64>,
}

#[derive(Serialize)]
struct Co2Data {
    co2_ppm: f32,
    temperature: f32,
    humidity: f32,
    model: &'static str,
    ok: bool,
}

#[derive(Serialize)]
struct StatusData<'a> {
    hostname: &'a str,
    platform: &'a str,
    uptime_seconds: u64,
    heap_free: usize,
    heap_used: usize,
    sd_card_mb: u32,
    sleep_pending: bool,
    wake_cause: &'a str,
    data_log_path: &'a str,
    data_log_interval_seconds: u64,
}

#[derive(Serialize)]
struct SensorData<'a> {
    name: &'a str,
    model: &'a str,
    transport: SensorTransportData,
    live: SensorLiveData,
}

#[derive(Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum SensorTransportData {
    I2c {
        bus_index: u8,
        address: u8,
        mux_channel: i8,
    },
    Modbus {
        channel: u8,
        slave_id: u8,
        register_address: u16,
    },
}

#[derive(Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum SensorLiveData {
    None,
    Co2 {
        ok: bool,
        co2_ppm: f32,
        temperature: f32,
        humidity: f32,
    },
    TemperatureHumidity {
        ok: bool,
        temperature_celsius: f32,
        relative_humidity_percent: f32,
    },
}

#[derive(Serialize)]
struct FileData {
    name: HeaplessString<32>,
    size: u32,
}

pub async fn api_handler() -> impl IntoResponse {
    let snapshot = system::snapshot();

    let mut sensor_list = heapless::Vec::<SensorData<'_>, { manager::MAX_SENSOR_COUNT }>::new();
    for sensor in snapshot.sensors.inventory.iter() {
        let transport_summary = sensor.transport_summary();
        let transport = if let Some(address) = transport_summary.address {
            SensorTransportData::I2c {
                bus_index: transport_summary.bus_index.unwrap_or_default(),
                address,
                mux_channel: transport_summary.mux_channel.unwrap_or(-1),
            }
        } else {
            SensorTransportData::Modbus {
                channel: transport_summary.channel.unwrap_or_default(),
                slave_id: transport_summary.slave_id.unwrap_or_default(),
                register_address: transport_summary.register_address.unwrap_or_default(),
            }
        };

        let live = if let Some(reading) = sensor.carbon_dioxide_reading() {
            SensorLiveData::Co2 {
                ok: reading.ok,
                co2_ppm: reading.co2_ppm,
                temperature: reading.temperature,
                humidity: reading.humidity,
            }
        } else if let Some(reading) = sensor.temperature_humidity_reading() {
            SensorLiveData::TemperatureHumidity {
                ok: reading.ok,
                temperature_celsius: reading.temperature_celsius,
                relative_humidity_percent: reading.relative_humidity_percent,
            }
        } else {
            SensorLiveData::None
        };

        let _ = sensor_list.push(SensorData {
            name: sensor.name,
            model: sensor.model,
            transport,
            live,
        });
    }

    let mut file_list = heapless::Vec::<FileData, 64>::new();
    if let Ok(entries) = crate::filesystems::sd::list_filesystem_entries() {
        for entry in &entries {
            let _ = file_list.push(FileData {
                name: entry.name.clone(),
                size: entry.size,
            });
        }
    }

    Json(ApiResponse {
        co2: Co2Data {
            co2_ppm: snapshot.sensors.carbon_dioxide.co2_ppm,
            temperature: snapshot.sensors.carbon_dioxide.temperature,
            humidity: snapshot.sensors.carbon_dioxide.humidity,
            model: snapshot.sensors.carbon_dioxide.model,
            ok: snapshot.sensors.carbon_dioxide.ok,
        },
        status: StatusData {
            hostname: snapshot.hostname,
            platform: snapshot.platform,
            uptime_seconds: snapshot.uptime_seconds,
            heap_free: snapshot.heap_free,
            heap_used: snapshot.heap_used,
            sd_card_mb: snapshot.storage.sd_card_size_mb,
            sleep_pending: snapshot.sleep.pending,
            wake_cause: snapshot.sleep.wake_cause,
            data_log_path: snapshot.data_logger.path,
            data_log_interval_seconds: snapshot.data_logger.interval_seconds,
        },
        sensors: sensor_list,
        files: file_list,
    })
    .into_response()
    .with_header("Access-Control-Allow-Origin", "*")
}
