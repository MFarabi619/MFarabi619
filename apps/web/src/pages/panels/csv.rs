use super::sensor_types::*;
use wasm_bindgen::JsCast;

pub fn download_csv(filename: &str, csv_content: &str) {
    let array = js_sys::Array::new();
    array.push(&wasm_bindgen::JsValue::from_str(csv_content));
    let mut options = web_sys::BlobPropertyBag::new();
    options.type_("text/csv");

    let Ok(blob) = web_sys::Blob::new_with_str_sequence_and_options(&array, &options) else {
        return;
    };
    let Ok(url) = web_sys::Url::create_object_url_with_blob(&blob) else {
        return;
    };

    if let Some(document) = web_sys::window().and_then(|w| w.document()) {
        if let Ok(anchor) = document.create_element("a") {
            let _ = anchor.set_attribute("href", &url);
            let _ = anchor.set_attribute("download", filename);
            let anchor: web_sys::HtmlElement = anchor.unchecked_into();
            anchor.click();
        }
    }

    let _ = web_sys::Url::revoke_object_url(&url);
}

pub trait CsvRow {
    fn header(sample: &[Self]) -> String
    where
        Self: Sized;
    fn to_row(&self) -> String;
}

impl CsvRow for Co2Row {
    fn header(_: &[Self]) -> String {
        "#,CO2_PPM,TEMP_C,HUMIDITY_PCT,TIME".to_string()
    }

    fn to_row(&self) -> String {
        format!(
            "{},{},{},{},{}",
            self.row, self.co2_ppm, self.temperature, self.humidity, self.time
        )
    }
}

impl CsvRow for TemperatureHumidityRow {
    fn header(sample: &[Self]) -> String {
        let sensor_count = sample.first().map(|row| row.sensors.len()).unwrap_or(0);
        let mut header = String::from("#,");
        for i in 0..sensor_count {
            header.push_str(&format!("TEMP_{i}_C,RH_{i}_PCT,"));
        }
        header.push_str("TIME");
        header
    }

    fn to_row(&self) -> String {
        let mut row = format!("{},", self.row);
        for sensor in &self.sensors {
            if sensor.read_ok {
                row.push_str(&format!(
                    "{},{},",
                    sensor.temperature_celsius, sensor.relative_humidity_percent
                ));
            } else {
                row.push_str(",,");
            }
        }
        row.push_str(&self.time);
        row
    }
}

impl CsvRow for VoltageRow {
    fn header(_: &[Self]) -> String {
        "#,CH0_V,CH0_C,CH1_V,CH1_C,CH2_V,CH2_C,CH3_V,CH3_C,TIME".to_string()
    }

    fn to_row(&self) -> String {
        let mut row = format!("{}", self.row);
        for (voltage, temperature) in self.channels.iter().zip(self.temperatures.iter()) {
            row.push_str(&format!(",{voltage:.4},{temperature:.6}"));
        }
        row.push_str(&format!(",{}", self.time));
        row
    }
}

impl CsvRow for PressureRow {
    fn header(_: &[Self]) -> String {
        "#,MODEL,PRESSURE_HPA,TEMP_C,TIME".to_string()
    }

    fn to_row(&self) -> String {
        format!(
            "{},{},{:.2},{:.1},{}",
            self.row, self.model, self.pressure_hpa, self.temperature_celsius, self.time
        )
    }
}

impl CsvRow for RainfallRow {
    fn header(_: &[Self]) -> String {
        "#,RAINFALL_MM,TIME".to_string()
    }

    fn to_row(&self) -> String {
        format!("{},{:.1},{}", self.row, self.rainfall_millimeters, self.time)
    }
}

impl CsvRow for SoilRow {
    fn header(_: &[Self]) -> String {
        "TIME,#,ID,MODEL,TEMPERATURE_CELSIUS,MOISTURE_PERCENT,PH,ELECTRICAL_CONDUCTIVITY_US_CM,SALINITY_MG_L,TOTAL_DISSOLVED_SOLIDS_PPM,TEMPERATURE_CALIBRATION,MOISTURE_CALIBRATION,CONDUCTIVITY_CALIBRATION,CONDUCTIVITY_TEMPERATURE_COEFFICIENT,SALINITY_COEFFICIENT,TDS_COEFFICIENT".to_string()
    }

    fn to_row(&self) -> String {
        let ph = self.ph.map(|value| format!("{value:.1}")).unwrap_or_else(|| "N/A".into());
        let conductivity = self.conductivity.map(|value| value.to_string()).unwrap_or_else(|| "N/A".into());
        let salinity = self.salinity.map(|value| value.to_string()).unwrap_or_else(|| "N/A".into());
        let tds = self.tds.map(|value| value.to_string()).unwrap_or_else(|| "N/A".into());
        let temperature_calibration = self.temperature_calibration.map(|value| format!("{value:.1}")).unwrap_or_else(|| "N/A".into());
        let moisture_calibration = self.moisture_calibration.map(|value| format!("{value:.1}")).unwrap_or_else(|| "N/A".into());
        let conductivity_calibration = self.conductivity_calibration.map(|value| value.to_string()).unwrap_or_else(|| "N/A".into());
        let conductivity_temperature_coefficient = self.conductivity_temperature_coefficient.map(|value| format!("{value:.1}")).unwrap_or_else(|| "N/A".into());
        let salinity_coefficient = self.salinity_coefficient.map(|value| format!("{value:.2}")).unwrap_or_else(|| "N/A".into());
        let tds_coefficient = self.tds_coefficient.map(|value| format!("{value:.2}")).unwrap_or_else(|| "N/A".into());
        format!(
            "{},{},{},{},{:.1},{:.1},{},{},{},{},{},{},{},{},{},{}",
            self.time, self.row, self.address, self.model,
            self.temperature_celsius, self.moisture_percent,
            ph, conductivity, salinity, tds,
            temperature_calibration, moisture_calibration, conductivity_calibration,
            conductivity_temperature_coefficient, salinity_coefficient, tds_coefficient
        )
    }
}

impl CsvRow for CurrentRow {
    fn header(_: &[Self]) -> String {
        "#,CURRENT_MA,BUS_V,SHUNT_MV,POWER_MW,ENERGY_J,CHARGE_C,DIE_TEMP_C,TIME".to_string()
    }

    fn to_row(&self) -> String {
        format!(
            "{},{:.3},{:.4},{:.4},{:.3},{:.3},{:.6},{:.1},{}",
            self.row, self.current_milliamps, self.bus_voltage,
            self.shunt_voltage_millivolts, self.power_milliwatts,
            self.energy_joules, self.charge_coulombs,
            self.die_temperature_celsius, self.time
        )
    }
}

impl CsvRow for WindSpeedRow {
    fn header(_: &[Self]) -> String {
        "#,WIND_SPEED_KMH,TIME".to_string()
    }

    fn to_row(&self) -> String {
        format!("{},{:.1},{}", self.row, self.kilometers_per_hour, self.time)
    }
}

impl CsvRow for WindDirectionRow {
    fn header(_: &[Self]) -> String {
        "#,DEGREES,ANGLE_SLICE,TIME".to_string()
    }

    fn to_row(&self) -> String {
        format!("{},{:.1},{},{}", self.row, self.degrees, self.angle_slice, self.time)
    }
}

impl CsvRow for SolarRadiationRow {
    fn header(_: &[Self]) -> String {
        "#,WATTS_PER_M2,TIME".to_string()
    }

    fn to_row(&self) -> String {
        format!("{},{},{}", self.row, self.watts_per_square_meter, self.time)
    }
}

pub fn build_csv<T: CsvRow>(readings: &[T]) -> String {
    let mut csv = T::header(readings);
    csv.push('\n');
    for row in readings {
        csv.push_str(&row.to_row());
        csv.push('\n');
    }
    csv
}
