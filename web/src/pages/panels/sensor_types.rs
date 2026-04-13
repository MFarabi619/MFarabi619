#[derive(Clone, Copy, PartialEq)]
pub enum MeasurementTab {
    Voltage,
    Current,
    CarbonDioxide,
    TemperatureHumidity,
}

impl MeasurementTab {
    pub fn to_value(self) -> String {
        match self {
            Self::TemperatureHumidity => "temp_humidity",
            Self::Voltage => "voltage",
            Self::Current => "current",
            Self::CarbonDioxide => "co2",
        }
        .to_string()
    }

    pub fn from_value(s: &str) -> Self {
        match s {
            "temp_humidity" => Self::TemperatureHumidity,
            "voltage" => Self::Voltage,
            "current" => Self::Current,
            "co2" => Self::CarbonDioxide,
            _ => Self::CarbonDioxide,
        }
    }
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
