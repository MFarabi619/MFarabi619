#[derive(Clone, Copy, PartialEq)]
pub enum MeasurementTab {
    Voltage,
    Current,
    CarbonDioxide,
    TemperatureHumidity,
    Pressure,
    Rainfall,
    Soil,
    WindSpeed,
    WindDirection,
    SolarRadiation,
}

impl MeasurementTab {
    pub fn to_value(self) -> String {
        match self {
            Self::TemperatureHumidity => "temp_humidity",
            Self::Voltage => "voltage",
            Self::Current => "current",
            Self::CarbonDioxide => "co2",
            Self::Pressure => "pressure",
            Self::Rainfall => "rainfall",
            Self::Soil => "soil",
            Self::WindSpeed => "wind_speed",
            Self::WindDirection => "wind_direction",
            Self::SolarRadiation => "solar_radiation",
        }
        .to_string()
    }

    pub fn from_value(s: &str) -> Self {
        match s {
            "temp_humidity" => Self::TemperatureHumidity,
            "voltage" => Self::Voltage,
            "current" => Self::Current,
            "co2" => Self::CarbonDioxide,
            "pressure" => Self::Pressure,
            "rainfall" => Self::Rainfall,
            "soil" => Self::Soil,
            "wind_speed" => Self::WindSpeed,
            "wind_direction" => Self::WindDirection,
            "solar_radiation" => Self::SolarRadiation,
            _ => Self::TemperatureHumidity,
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::TemperatureHumidity => "Temperature & Humidity",
            Self::Voltage => "Voltage",
            Self::Current => "Current",
            Self::CarbonDioxide => "CO\u{2082}",
            Self::Pressure => "Pressure",
            Self::Rainfall => "Rainfall",
            Self::Soil => "Soil",
            Self::WindSpeed => "Wind Speed",
            Self::WindDirection => "Wind Direction",
            Self::SolarRadiation => "Solar Radiation",
        }
    }

    pub fn is_available(&self, avail: &super::sensor_feed::SensorAvailability) -> bool {
        match self {
            Self::TemperatureHumidity => avail.temperature_humidity,
            Self::Voltage => avail.voltage,
            Self::Current => avail.current,
            Self::CarbonDioxide => avail.co2,
            Self::Pressure => avail.pressure,
            Self::Rainfall => avail.rainfall,
            Self::Soil => avail.soil,
            Self::WindSpeed => avail.wind_speed,
            Self::WindDirection => avail.wind_direction,
            Self::SolarRadiation => avail.solar_radiation,
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
    pub temperatures: Vec<f64>,
    pub time: String,
}

#[derive(Clone)]
pub struct CurrentRow {
    pub row: usize,
    pub current_milliamps: f64,
    pub bus_voltage: f64,
    pub shunt_voltage_millivolts: f64,
    pub power_milliwatts: f64,
    pub energy_joules: f64,
    pub charge_coulombs: f64,
    pub die_temperature_celsius: f64,
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

#[derive(Clone)]
pub struct RainfallRow {
    pub row: usize,
    pub rainfall_millimeters: f64,
    pub time: String,
}

#[derive(Clone)]
pub struct SoilRow {
    pub row: usize,
    pub address: u8,
    pub model: &'static str,
    pub temperature_celsius: f64,
    pub moisture_percent: f64,
    pub ph: Option<f64>,
    pub conductivity: Option<u16>,
    pub salinity: Option<u16>,
    pub tds: Option<u16>,
    pub temperature_calibration: Option<f64>,
    pub moisture_calibration: Option<f64>,
    pub conductivity_calibration: Option<u16>,
    pub conductivity_temperature_coefficient: Option<f64>,
    pub salinity_coefficient: Option<f64>,
    pub tds_coefficient: Option<f64>,
    pub time: String,
}

#[derive(Clone)]
pub struct WindSpeedRow {
    pub row: usize,
    pub kilometers_per_hour: f64,
    pub time: String,
}

#[derive(Clone)]
pub struct WindDirectionRow {
    pub row: usize,
    pub degrees: f64,
    pub angle_slice: u8,
    pub time: String,
}

#[derive(Clone)]
pub struct SolarRadiationRow {
    pub row: usize,
    pub watts_per_square_meter: u16,
    pub time: String,
}
