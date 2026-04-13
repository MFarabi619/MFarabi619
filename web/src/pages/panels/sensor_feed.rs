use dioxus::prelude::*;
use crate::services::CloudEventsService;
use super::sensor_types::*;
use super::now_time_string;

pub const ENABLE_VOLTAGE: bool = true;
pub const ENABLE_CURRENT: bool = false;
pub const ENABLE_CO2: bool = true;
pub const ENABLE_TEMPERATURE_HUMIDITY: bool = true;

pub async fn fetch_and_add_sensor_readings(
    url: &str,
    mut last_event_time: Signal<String>,
    mut co2_readings: Signal<Vec<Co2Row>>,
    mut temperature_humidity_readings: Signal<Vec<TemperatureHumidityRow>>,
    mut voltage_readings: Signal<Vec<VoltageRow>>,
) -> bool {
    let Ok(events) = CloudEventsService::fetch(url).await else {
        return false;
    };

    let event_time = events.first().map(|e| e.time.clone()).unwrap_or_default();
    if event_time == *last_event_time.read() && !event_time.is_empty() {
        return false;
    }
    last_event_time.set(event_time);

    let mut added = false;
    let time = now_time_string();

    for event in &events {
        let Some(data) = event.data.as_object() else { continue };

        match event.event_type.as_str() {
            t if t == "sensors.carbon_dioxide.v1" || data.contains_key("co2_ppm") => {
                let co2_ppm = data.get("co2_ppm").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let temperature = data.get("temperature").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let humidity = data.get("humidity").and_then(|v| v.as_f64()).unwrap_or(0.0);

                // HACK: firmware sends zeroed readings when sensor data isn't ready,
                // remove once cloudevents.cpp skips not-ready CO2 events
                if co2_ppm == 0.0 && temperature == 0.0 && humidity == 0.0 {
                    continue;
                }

                let is_duplicate = co2_readings.read().last().is_some_and(|last|
                    last.co2_ppm == co2_ppm && last.temperature == temperature && last.humidity == humidity
                );
                if !is_duplicate {
                    let next_row = co2_readings.read().len() + 1;
                    co2_readings.write().push(Co2Row {
                        row: next_row,
                        co2_ppm, temperature, humidity,
                        time: time.clone(),
                    });
                    added = true;
                }
            }

            "sensors.temperature_and_humidity.v1" => {
                if let Some(sensors) = data.get("sensors").and_then(|v| v.as_array()) {
                    if sensors.is_empty() { continue; }
                    let readings: Vec<TemperatureHumidityReading> = sensors.iter().map(|s| {
                        TemperatureHumidityReading {
                            index: s.get("index").and_then(|v| v.as_u64()).unwrap_or(0) as usize,
                            read_ok: s.get("read_ok").and_then(|v| v.as_bool()).unwrap_or(false),
                            temperature_celsius: s.get("temperature_celsius").and_then(|v| v.as_f64()).unwrap_or(0.0),
                            relative_humidity_percent: s.get("relative_humidity_percent").and_then(|v| v.as_f64()).unwrap_or(0.0),
                        }
                    }).collect();
                    let next_row = temperature_humidity_readings.read().len() + 1;
                    temperature_humidity_readings.write().push(TemperatureHumidityRow {
                        row: next_row,
                        sensors: readings,
                        time: time.clone(),
                    });
                    added = true;
                }
            }

            "sensors.power.v1" => {
                if data.get("read_ok").and_then(|v| v.as_bool()) == Some(true) {
                    let channels: Vec<f64> = data.get("voltage")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().filter_map(|v| v.as_f64()).collect())
                        .unwrap_or_default();

                    let is_duplicate = voltage_readings.read().last().is_some_and(|last|
                        last.channels == channels
                    );
                    if !is_duplicate {
                        let gain = data.get("gain").and_then(|v| v.as_str()).unwrap_or("").to_string();
                        let next_row = voltage_readings.read().len() + 1;
                        voltage_readings.write().push(VoltageRow {
                            row: next_row,
                            gain, channels,
                            time: time.clone(),
                        });
                        added = true;
                    }
                }
            }

            _ => {}
        }
    }

    added
}
