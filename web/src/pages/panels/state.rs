use super::sensor_feed::SensorAvailability;
use super::sensor_types::{
    Co2Row, CurrentRow, PressureRow, RainfallRow, SoilRow, SolarRadiationRow,
    TemperatureHumidityRow, VoltageRow, WindDirectionRow, WindSpeedRow,
};
use dioxus::prelude::*;

#[derive(Clone)]
pub struct MeasurementState {
    pub last_event_time: Signal<String>,
    pub availability: Signal<SensorAvailability>,
    pub co2_readings: Signal<Vec<Co2Row>>,
    pub temperature_humidity_readings: Signal<Vec<TemperatureHumidityRow>>,
    pub voltage_readings: Signal<Vec<VoltageRow>>,
    pub current_readings: Signal<Vec<CurrentRow>>,
    pub pressure_readings: Signal<Vec<PressureRow>>,
    pub rainfall_readings: Signal<Vec<RainfallRow>>,
    pub soil_readings: Signal<Vec<SoilRow>>,
    pub wind_speed_readings: Signal<Vec<WindSpeedRow>>,
    pub wind_direction_readings: Signal<Vec<WindDirectionRow>>,
    pub solar_radiation_readings: Signal<Vec<SolarRadiationRow>>,
}
