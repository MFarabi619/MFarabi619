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
        "#,CH0_V,CH1_V,CH2_V,CH3_V,TIME".to_string()
    }

    fn to_row(&self) -> String {
        let mut row = format!("{},", self.row);
        for (i, voltage) in self.channels.iter().enumerate() {
            row.push_str(&format!("{voltage:.4}"));
            if i < self.channels.len() - 1 {
                row.push(',');
            }
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

pub fn build_csv<T: CsvRow>(readings: &[T]) -> String {
    let mut csv = T::header(readings);
    csv.push('\n');
    for row in readings {
        csv.push_str(&row.to_row());
        csv.push('\n');
    }
    csv
}
