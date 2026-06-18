use dioxus::prelude::*;
use crate::services::{CloudEventsService, SensorsService};
use super::sensor_types::*;
use super::now_time_string;

#[derive(Clone, Copy, Default)]
pub struct SensorAvailability {
    pub temperature_humidity: bool,
    pub voltage: bool,
    pub current: bool,
    pub co2: bool,
    pub pressure: bool,
    pub rainfall: bool,
    pub soil: bool,
    pub wind_speed: bool,
    pub wind_direction: bool,
    pub solar_radiation: bool,
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
    availability.current = inv.current_available;
    availability.co2 = inv.co2_available;
    availability.pressure = inv.barometric_pressure_available;
    availability.rainfall = inv.rainfall_available;
    availability.soil = inv.soil_probe_count > 0;
    availability.wind_speed = inv.wind_speed_available;
    availability.wind_direction = inv.wind_direction_available;
    availability.solar_radiation = inv.solar_radiation_available;
    true
}

use super::state::MeasurementState;

enum SensorReading {
    Co2 { ppm: f64, temp: f64, humidity: f64 },
    TemperatureHumidity { sensors: Vec<TemperatureHumidityReading>, model: String },
    Voltage { gain: String, channels: Vec<f64>, temperatures: Vec<f64> },
    Current {
        current_milliamps: f64,
        bus_voltage: f64,
        shunt_voltage_millivolts: f64,
        power_milliwatts: f64,
        energy_joules: f64,
        charge_coulombs: f64,
        die_temperature_celsius: f64,
    },
    Pressure { model: String, pressure_hpa: f64, temp: f64 },
    Rainfall { millimeters: f64 },
    Soil {
        address: u8,
        model: &'static str,
        temperature_celsius: f64,
        moisture_percent: f64,
        ph: Option<f64>,
        conductivity: Option<u16>,
        salinity: Option<u16>,
        tds: Option<u16>,
        temperature_calibration: Option<f64>,
        moisture_calibration: Option<f64>,
        conductivity_calibration: Option<u16>,
        conductivity_temperature_coefficient: Option<f64>,
        salinity_coefficient: Option<f64>,
        tds_coefficient: Option<f64>,
    },
    WindSpeed { kilometers_per_hour: f64 },
    WindDirection { degrees: f64, angle_slice: u8 },
    SolarRadiation { watts_per_square_meter: u16 },
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

            "sensors.current.v1" => {
                readings.push(SensorReading::Current {
                    current_milliamps: data.get("current_mA").and_then(|v| v.as_f64()).unwrap_or(0.0),
                    bus_voltage: data.get("bus_voltage_V").and_then(|v| v.as_f64()).unwrap_or(0.0),
                    shunt_voltage_millivolts: data.get("shunt_voltage_mV").and_then(|v| v.as_f64()).unwrap_or(0.0),
                    power_milliwatts: data.get("power_mW").and_then(|v| v.as_f64()).unwrap_or(0.0),
                    energy_joules: data.get("energy_J").and_then(|v| v.as_f64()).unwrap_or(0.0),
                    charge_coulombs: data.get("charge_C").and_then(|v| v.as_f64()).unwrap_or(0.0),
                    die_temperature_celsius: data.get("die_temperature_C").and_then(|v| v.as_f64()).unwrap_or(0.0),
                });
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
                let parse_probe = |probe: &serde_json::Value| -> Option<SensorReading> {
                    if probe.get("read_ok").and_then(|value| value.as_bool()) != Some(true) { return None; }
                    let optional_u16 = |key: &str, flag: &str| -> Option<u16> {
                        if probe.get(flag).and_then(|value| value.as_bool()) == Some(true) {
                            Some(probe.get(key).and_then(|value| value.as_u64()).unwrap_or(0) as u16)
                        } else {
                            None
                        }
                    };
                    let ph = if probe.get("has_ph").and_then(|value| value.as_bool()) == Some(true) {
                        Some(probe.get("ph").and_then(|value| value.as_f64()).unwrap_or(0.0))
                    } else {
                        None
                    };
                    let conductivity = optional_u16("conductivity", "has_conductivity");
                    let has_calibration = probe.get("has_calibration").and_then(|value| value.as_bool()) == Some(true);
                    let model: &'static str = match probe.get("model").and_then(|value| value.as_str()) {
                        Some("SEN0600") => "SEN0600",
                        Some("SEN0601") => "SEN0601",
                        Some("SEN0604") => "SEN0604",
                        _ => match (conductivity.is_some(), ph.is_some()) {
                            (false, false) => "SEN0600",
                            (true, false)  => "SEN0601",
                            (true, true)   => "SEN0604",
                            _              => "Unknown",
                        },
                    };
                    let optional_calibration_f64 = |key: &str| -> Option<f64> {
                        if has_calibration { probe.get(key).and_then(|value| value.as_f64()) } else { None }
                    };
                    let optional_calibration_u16 = |key: &str| -> Option<u16> {
                        if has_calibration { probe.get(key).and_then(|value| value.as_u64()).map(|value| value as u16) } else { None }
                    };
                    Some(SensorReading::Soil {
                        address: probe.get("slave_id").and_then(|value| value.as_u64()).unwrap_or(0) as u8,
                        model,
                        temperature_celsius: probe.get("temperature_celsius").and_then(|value| value.as_f64()).unwrap_or(0.0),
                        moisture_percent: probe.get("moisture_percent").and_then(|value| value.as_f64()).unwrap_or(0.0),
                        ph,
                        conductivity,
                        salinity: optional_u16("salinity", "has_salinity"),
                        tds: optional_u16("tds", "has_tds"),
                        temperature_calibration: optional_calibration_f64("temperature_calibration"),
                        moisture_calibration: optional_calibration_f64("moisture_calibration"),
                        conductivity_calibration: optional_calibration_u16("conductivity_calibration"),
                        conductivity_temperature_coefficient: optional_calibration_f64("conductivity_temperature_coefficient"),
                        salinity_coefficient: optional_calibration_f64("salinity_coefficient"),
                        tds_coefficient: optional_calibration_f64("tds_coefficient"),
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

            "sensors.wind_speed.v1" => {
                let kilometers_per_hour = data.get("wind_speed_kilometers_per_hour")
                    .and_then(|v| v.as_f64()).unwrap_or(0.0);
                readings.push(SensorReading::WindSpeed { kilometers_per_hour });
            }

            "sensors.wind_direction.v1" => {
                let degrees = data.get("wind_direction_degrees")
                    .and_then(|v| v.as_f64()).unwrap_or(0.0);
                let angle_slice = data.get("wind_direction_angle_slice")
                    .and_then(|v| v.as_u64()).unwrap_or(0) as u8;
                readings.push(SensorReading::WindDirection { degrees, angle_slice });
            }

            "sensors.solar_radiation.v1" => {
                let watts_per_square_meter = data.get("watts_per_square_meter")
                    .and_then(|v| v.as_u64()).unwrap_or(0) as u16;
                readings.push(SensorReading::SolarRadiation { watts_per_square_meter });
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
                SensorReading::Current {
                    current_milliamps, bus_voltage, shunt_voltage_millivolts,
                    power_milliwatts, energy_joules, charge_coulombs,
                    die_temperature_celsius,
                } => {
                    if !state.availability.read().current {
                        state.availability.write().current = true;
                    }
                    let next_row = state.current_readings.read().len() + 1;
                    state.current_readings.write().push(CurrentRow {
                        row: next_row,
                        current_milliamps: *current_milliamps,
                        bus_voltage: *bus_voltage,
                        shunt_voltage_millivolts: *shunt_voltage_millivolts,
                        power_milliwatts: *power_milliwatts,
                        energy_joules: *energy_joules,
                        charge_coulombs: *charge_coulombs,
                        die_temperature_celsius: *die_temperature_celsius,
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
                SensorReading::Soil {
                    address, model, temperature_celsius, moisture_percent,
                    ph, conductivity, salinity, tds,
                    temperature_calibration, moisture_calibration, conductivity_calibration,
                    conductivity_temperature_coefficient, salinity_coefficient, tds_coefficient,
                } => {
                    if !state.availability.read().soil {
                        state.availability.write().soil = true;
                    }
                    let next_row = state.soil_readings.read().len() + 1;
                    state.soil_readings.write().push(SoilRow {
                        row: next_row,
                        address: *address,
                        model,
                        temperature_celsius: *temperature_celsius,
                        moisture_percent: *moisture_percent,
                        ph: *ph,
                        conductivity: *conductivity,
                        salinity: *salinity,
                        tds: *tds,
                        temperature_calibration: *temperature_calibration,
                        moisture_calibration: *moisture_calibration,
                        conductivity_calibration: *conductivity_calibration,
                        conductivity_temperature_coefficient: *conductivity_temperature_coefficient,
                        salinity_coefficient: *salinity_coefficient,
                        tds_coefficient: *tds_coefficient,
                        time: prev_time.clone(),
                    });
                    added = true;
                }
                SensorReading::WindSpeed { kilometers_per_hour } => {
                    if !state.availability.read().wind_speed {
                        state.availability.write().wind_speed = true;
                    }
                    let next_row = state.wind_speed_readings.read().len() + 1;
                    state.wind_speed_readings.write().push(WindSpeedRow {
                        row: next_row,
                        kilometers_per_hour: *kilometers_per_hour,
                        time: prev_time.clone(),
                    });
                    added = true;
                }
                SensorReading::WindDirection { degrees, angle_slice } => {
                    if !state.availability.read().wind_direction {
                        state.availability.write().wind_direction = true;
                    }
                    let next_row = state.wind_direction_readings.read().len() + 1;
                    state.wind_direction_readings.write().push(WindDirectionRow {
                        row: next_row,
                        degrees: *degrees,
                        angle_slice: *angle_slice,
                        time: prev_time.clone(),
                    });
                    added = true;
                }
                SensorReading::SolarRadiation { watts_per_square_meter } => {
                    if !state.availability.read().solar_radiation {
                        state.availability.write().solar_radiation = true;
                    }
                    let next_row = state.solar_radiation_readings.read().len() + 1;
                    state.solar_radiation_readings.write().push(SolarRadiationRow {
                        row: next_row,
                        watts_per_square_meter: *watts_per_square_meter,
                        time: prev_time.clone(),
                    });
                    added = true;
                }
            }
        }

        added
    }
}
