use super::sensor_feed::SensorAvailability;
use super::sensor_types::{Co2Row, PressureRow, TemperatureHumidityRow, VoltageRow};
use dioxus::prelude::*;

#[derive(Clone)]
pub struct MeasurementState {
    pub last_event_time: Signal<String>,
    pub availability: Signal<SensorAvailability>,
    pub co2_readings: Signal<Vec<Co2Row>>,
    pub temperature_humidity_readings: Signal<Vec<TemperatureHumidityRow>>,
    pub voltage_readings: Signal<Vec<VoltageRow>>,
    pub pressure_readings: Signal<Vec<PressureRow>>,
}
