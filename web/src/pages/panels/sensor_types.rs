#[derive(Clone, Copy, PartialEq)]
pub enum MeasurementTab {
    Voltage,
    Current,
    CarbonDioxide,
    TemperatureHumidity,
}

#[derive(Clone)]
pub struct Co2Row {
    pub row: usize,
    pub co2_ppm: f64,
    pub temperature: f64,
    pub humidity: f64,
    pub time: String,
}

#[derive(Clone)]
pub struct TemperatureHumidityReading {
    pub index: usize,
    pub read_ok: bool,
    pub temperature_celsius: f64,
    pub relative_humidity_percent: f64,
}

#[derive(Clone)]
pub struct TemperatureHumidityRow {
    pub row: usize,
    pub sensors: Vec<TemperatureHumidityReading>,
    pub time: String,
}

#[derive(Clone)]
pub struct VoltageRow {
    pub row: usize,
    pub gain: String,
    pub channels: Vec<f64>,
    pub time: String,
}
