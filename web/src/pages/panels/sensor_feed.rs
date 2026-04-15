use dioxus::prelude::*;
use crate::services::{CloudEventsService, SensorsService};
use super::sensor_types::*;
use super::now_time_string;

#[derive(Clone, Copy, Default)]
pub struct SensorAvailability {
    pub temperature_humidity: bool,
    pub voltage: bool,
    pub co2: bool,
    pub pressure: bool,
}

pub async fn load_inventory(url: &str, availability: &mut SensorAvailability) -> bool {
    let Ok(response) = SensorsService::inventory(url).await else {
        return false;
    };
    if !response.ok {
        return false;
    }
    let inv = response.data;
    availability.temperature_humidity = inv.temperature_humidity_count > 0;
    availability.voltage = inv.voltage_available;
    availability.co2 = inv.co2_available;
    availability.pressure = inv.barometric_pressure_available;
    true
}

pub async fn fetch_and_add_sensor_readings(
    url: &str,
    mut last_event_time: Signal<String>,
    mut co2_readings: Signal<Vec<Co2Row>>,
    mut temperature_humidity_readings: Signal<Vec<TemperatureHumidityRow>>,
    mut voltage_readings: Signal<Vec<VoltageRow>>,
    mut pressure_readings: Signal<Vec<PressureRow>>,
    mut availability: Signal<SensorAvailability>,
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

                if co2_ppm == 0.0 && temperature == 0.0 && humidity == 0.0 {
                    continue;
                }

                if !availability.read().co2 {
                    availability.write().co2 = true;
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
                    if !availability.read().temperature_humidity {
                        availability.write().temperature_humidity = true;
                    }
                    let mut model_from_first = String::new();
                    let readings: Vec<TemperatureHumidityReading> = sensors.iter().map(|s| {
                        let model = s.get("model").and_then(|v| v.as_str()).unwrap_or("").to_string();
                        if model_from_first.is_empty() && !model.is_empty() {
                            model_from_first = model.clone();
                        }
                        TemperatureHumidityReading {
                            index: s.get("index").and_then(|v| v.as_u64()).unwrap_or(0) as usize,
                            read_ok: s.get("read_ok").and_then(|v| v.as_bool()).unwrap_or(false),
                            model,
                            temperature_celsius: s.get("temperature_celsius").and_then(|v| v.as_f64()).unwrap_or(0.0),
                            relative_humidity_percent: s.get("relative_humidity_percent").and_then(|v| v.as_f64()).unwrap_or(0.0),
                        }
                    }).collect();
                    let next_row = temperature_humidity_readings.read().len() + 1;
                    temperature_humidity_readings.write().push(TemperatureHumidityRow {
                        row: next_row,
                        sensors: readings,
                        default_model: model_from_first,
                        time: time.clone(),
                    });
                    added = true;
                }
            }

            "sensors.power.v1" => {
                if data.get("read_ok").and_then(|v| v.as_bool()) == Some(true) {
                    if !availability.read().voltage {
                        availability.write().voltage = true;
                    }
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

            "sensors.barometric_pressure.v1" => {
                let pressure_hpa = data.get("pressure_hpa").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let temperature = data.get("temperature_celsius").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let model = data.get("model").and_then(|v| v.as_str()).unwrap_or("").to_string();

                if pressure_hpa == 0.0 && temperature == 0.0 {
                    continue;
                }

                if !availability.read().pressure {
                    availability.write().pressure = true;
                }

                let is_duplicate = pressure_readings.read().last().is_some_and(|last|
                    last.pressure_hpa == pressure_hpa && last.temperature_celsius == temperature
                );
                if !is_duplicate {
                    let next_row = pressure_readings.read().len() + 1;
                    pressure_readings.write().push(PressureRow {
                        row: next_row,
                        model,
                        pressure_hpa,
                        temperature_celsius: temperature,
                        time: time.clone(),
                    });
                    added = true;
                }
            }

            _ => {}
        }
    }

    added
}
