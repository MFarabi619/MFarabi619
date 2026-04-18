#[derive(Clone, Copy, PartialEq)]
pub enum MeasurementTab {
    Voltage,
    CarbonDioxide,
    TemperatureHumidity,
    Pressure,
}

impl MeasurementTab {
    pub fn to_value(self) -> String {
        match self {
            Self::TemperatureHumidity => "temp_humidity",
            Self::Voltage => "voltage",
            Self::CarbonDioxide => "co2",
            Self::Pressure => "pressure",
        }
        .to_string()
    }

    pub fn from_value(s: &str) -> Self {
        match s {
            "temp_humidity" => Self::TemperatureHumidity,
            "voltage" => Self::Voltage,
            "co2" => Self::CarbonDioxide,
            "pressure" => Self::Pressure,
            _ => Self::TemperatureHumidity,
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::TemperatureHumidity => "Temperature & Humidity",
            Self::Voltage => "Voltage",
            Self::CarbonDioxide => "CO\u{2082}",
            Self::Pressure => "Pressure",
        }
    }

    pub fn is_available(&self, avail: &super::sensor_feed::SensorAvailability) -> bool {
        match self {
            Self::TemperatureHumidity => avail.temperature_humidity,
            Self::Voltage => avail.voltage,
            Self::CarbonDioxide => avail.co2,
            Self::Pressure => avail.pressure,
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

#[derive(Clone, PartialEq)]
pub struct TemperatureHumidityReading {
    pub read_ok: bool,
    pub temperature_celsius: f64,
    pub relative_humidity_percent: f64,
}

#[derive(Clone)]
pub struct TemperatureHumidityRow {
    pub row: usize,
    pub sensors: Vec<TemperatureHumidityReading>,
    pub default_model: String,
    pub time: String,
}

#[derive(Clone)]
pub struct VoltageRow {
    pub row: usize,
    pub gain: String,
    pub channels: Vec<f64>,
    pub time: String,
}

#[derive(Clone)]
pub struct PressureRow {
    pub row: usize,
    pub model: String,
    pub pressure_hpa: f64,
    pub temperature_celsius: f64,
    pub time: String,
}
