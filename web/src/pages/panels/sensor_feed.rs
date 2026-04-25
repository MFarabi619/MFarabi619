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
    pub rainfall: bool,
    pub soil: bool,
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
    availability.rainfall = inv.rainfall_available;
    availability.soil = inv.soil_probe_count > 0;
    true
}

use super::state::MeasurementState;

enum SensorReading {
    Co2 { ppm: f64, temp: f64, humidity: f64 },
    TemperatureHumidity { sensors: Vec<TemperatureHumidityReading>, model: String },
    Voltage { gain: String, channels: Vec<f64>, temperatures: Vec<f64> },
    Pressure { model: String, pressure_hpa: f64, temp: f64 },
    Rainfall { millimeters: f64 },
    Soil { slave_id: u8, moisture_percent: f64, temperature_celsius: f64, conductivity: u16, salinity: u16, tds: u16, has_ph: bool, ph: f64 },
}

struct ParsedEvents {
    event_time: String,
    time: String,
    readings: Vec<SensorReading>,
}

fn parse_events(events: &[crate::api::CloudEvent]) -> Option<ParsedEvents> {
    let event_time = events.first()?.time.clone();
    if event_time.is_empty() {
        return None;
    }
    
    let time = now_time_string();
    let mut readings = Vec::new();

    for event in events {
        let Some(data) = event.data.as_object() else { continue };

        match event.event_type.as_str() {
            t if t == "sensors.carbon_dioxide.v1" || data.contains_key("co2_ppm") => {
                let ppm = data.get("co2_ppm").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let temp = data.get("temperature").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let humidity = data.get("humidity").and_then(|v| v.as_f64()).unwrap_or(0.0);
                if ppm != 0.0 || temp != 0.0 || humidity != 0.0 {
                    readings.push(SensorReading::Co2 { ppm, temp, humidity });
                }
            }

            "sensors.temperature_and_humidity.v1" => {
                if let Some(sensors) = data.get("sensors").and_then(|v| v.as_array()) {
                    if !sensors.is_empty() {
                        let mut model = String::new();
                        let parsed: Vec<TemperatureHumidityReading> = sensors.iter().map(|s| {
                            let m = s.get("model").and_then(|v| v.as_str()).unwrap_or("").to_string();
                            if model.is_empty() && !m.is_empty() {
                                model = m;
                            }
                            TemperatureHumidityReading {
                                read_ok: s.get("read_ok").and_then(|v| v.as_bool()).unwrap_or(false),
                                temperature_celsius: s.get("temperature_celsius").and_then(|v| v.as_f64()).unwrap_or(0.0),
                                relative_humidity_percent: s.get("relative_humidity_percent").and_then(|v| v.as_f64()).unwrap_or(0.0),
                            }
                        }).collect();
                        readings.push(SensorReading::TemperatureHumidity { sensors: parsed, model });
                    }
                }
            }

            "sensors.power.v1" => {
                if data.get("read_ok").and_then(|v| v.as_bool()) == Some(true) {
                    let channels: Vec<f64> = data.get("voltage")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().filter_map(|v| v.as_f64()).collect())
                        .unwrap_or_default();
                    let temperatures: Vec<f64> = data.get("temperature_celsius")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().filter_map(|v| v.as_f64()).collect())
                        .unwrap_or_default();
                    let gain = data.get("gain").and_then(|v| v.as_str()).unwrap_or("").to_string();
                    readings.push(SensorReading::Voltage { gain, channels, temperatures });
                }
            }

            "sensors.barometric_pressure.v1" => {
                let pressure_hpa = data.get("pressure_hpa").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let temp = data.get("temperature_celsius").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let model = data.get("model").and_then(|v| v.as_str()).unwrap_or("").to_string();
                if pressure_hpa != 0.0 || temp != 0.0 {
                    readings.push(SensorReading::Pressure { model, pressure_hpa, temp });
                }
            }

            "sensors.rainfall.v1" => {
                let millimeters = data.get("rainfall_millimeters").and_then(|v| v.as_f64()).unwrap_or(0.0);
                readings.push(SensorReading::Rainfall { millimeters });
            }

            "sensors.soil.v1" => {
                let parse_probe = |s: &serde_json::Value| -> Option<SensorReading> {
                    if s.get("read_ok").and_then(|v| v.as_bool()) != Some(true) { return None; }
                    Some(SensorReading::Soil {
                        slave_id: s.get("slave_id").and_then(|v| v.as_u64()).unwrap_or(0) as u8,
                        moisture_percent: s.get("moisture_percent").and_then(|v| v.as_f64()).unwrap_or(0.0),
                        temperature_celsius: s.get("temperature_celsius").and_then(|v| v.as_f64()).unwrap_or(0.0),
                        conductivity: s.get("conductivity").and_then(|v| v.as_u64()).unwrap_or(0) as u16,
                        salinity: s.get("salinity").and_then(|v| v.as_u64()).unwrap_or(0) as u16,
                        tds: s.get("tds").and_then(|v| v.as_u64()).unwrap_or(0) as u16,
                        has_ph: s.get("has_ph").and_then(|v| v.as_bool()).unwrap_or(false),
                        ph: s.get("ph").and_then(|v| v.as_f64()).unwrap_or(0.0),
                    })
                };

                if let Some(sensors) = data.get("sensors").and_then(|v| v.as_array()) {
                    for sensor in sensors {
                        if let Some(reading) = parse_probe(sensor) {
                            readings.push(reading);
                        }
                    }
                } else if data.get("read_ok").and_then(|v| v.as_bool()) == Some(true) {
                    if let Some(reading) = parse_probe(&event.data) {
                        readings.push(reading);
                    }
                }
            }

            _ => {}
        }
    }

    Some(ParsedEvents { event_time, time, readings })
}

pub async fn fetch_and_add_sensor_readings(
    url: &str,
    mut state: Signal<MeasurementState>,
) -> bool {
    let Ok(events) = CloudEventsService::fetch(url).await else {
        return false;
    };

    let Some(parsed) = parse_events(&events) else {
        return false;
    };

    if parsed.event_time == *state.read().last_event_time.read() {
        return false;
    }

    {
        let mut state = state.write();
        state.last_event_time.set(parsed.event_time.clone());

        let prev_time = parsed.time.clone();
        let mut added = false;

        for reading in &parsed.readings {
            match reading {
                SensorReading::Co2 { ppm, temp, humidity } => {
                    if !state.availability.read().co2 {
                        state.availability.write().co2 = true;
                    }
                    let next_row = state.co2_readings.read().len() + 1;
                    state.co2_readings.write().push(Co2Row {
                        row: next_row,
                        co2_ppm: *ppm,
                        temperature: *temp,
                        humidity: *humidity,
                        time: prev_time.clone(),
                    });
                    added = true;
                }
                SensorReading::TemperatureHumidity { sensors, model } => {
                    if !state.availability.read().temperature_humidity {
                        state.availability.write().temperature_humidity = true;
                    }
                    let next_row = state.temperature_humidity_readings.read().len() + 1;
                    state.temperature_humidity_readings.write().push(TemperatureHumidityRow {
                        row: next_row,
                        sensors: sensors.clone(),
                        default_model: model.clone(),
                        time: prev_time.clone(),
                    });
                    added = true;
                }
                SensorReading::Voltage { gain, channels, temperatures } => {
                    if !state.availability.read().voltage {
                        state.availability.write().voltage = true;
                    }
                    let next_row = state.voltage_readings.read().len() + 1;
                    state.voltage_readings.write().push(VoltageRow {
                        row: next_row,
                        gain: gain.clone(),
                        channels: channels.clone(),
                        temperatures: temperatures.clone(),
                        time: prev_time.clone(),
                    });
                    added = true;
                }
                SensorReading::Pressure { model, pressure_hpa, temp } => {
                    if !state.availability.read().pressure {
                        state.availability.write().pressure = true;
                    }
                    let next_row = state.pressure_readings.read().len() + 1;
                    state.pressure_readings.write().push(PressureRow {
                        row: next_row,
                        model: model.clone(),
                        pressure_hpa: *pressure_hpa,
                        temperature_celsius: *temp,
                        time: prev_time.clone(),
                    });
                    added = true;
                }
                SensorReading::Rainfall { millimeters } => {
                    if !state.availability.read().rainfall {
                        state.availability.write().rainfall = true;
                    }
                    let next_row = state.rainfall_readings.read().len() + 1;
                    state.rainfall_readings.write().push(RainfallRow {
                        row: next_row,
                        rainfall_millimeters: *millimeters,
                        time: prev_time.clone(),
                    });
                    added = true;
                }
                SensorReading::Soil { slave_id, moisture_percent, temperature_celsius, conductivity, salinity, tds, has_ph, ph } => {
                    if !state.availability.read().soil {
                        state.availability.write().soil = true;
                    }
                    let next_row = state.soil_readings.read().len() + 1;
                    state.soil_readings.write().push(SoilRow {
                        row: next_row,
                        slave_id: *slave_id,
                        moisture_percent: *moisture_percent,
                        temperature_celsius: *temperature_celsius,
                        conductivity: *conductivity,
                        salinity: *salinity,
                        tds: *tds,
                        has_ph: *has_ph,
                        ph: *ph,
                        time: prev_time.clone(),
                    });
                    added = true;
                }
            }
        }

        added
    }
}
