use wasm_bindgen::JsCast;
use super::sensor_types::*;

pub fn download_csv(filename: &str, csv_content: &str) {
    let array = js_sys::Array::new();
    array.push(&wasm_bindgen::JsValue::from_str(csv_content));
    let mut options = web_sys::BlobPropertyBag::new();
    options.type_("text/csv");
    let blob = web_sys::Blob::new_with_str_sequence_and_options(&array, &options).unwrap();
    let url = web_sys::Url::create_object_url_with_blob(&blob).unwrap();

    let window = web_sys::window().unwrap();
    let document = window.document().unwrap();
    let anchor = document.create_element("a").unwrap();
    anchor.set_attribute("href", &url).unwrap();
    anchor.set_attribute("download", filename).unwrap();
    let anchor_element: web_sys::HtmlElement = anchor.unchecked_into();
    anchor_element.click();
    web_sys::Url::revoke_object_url(&url).unwrap();
}

pub fn build_co2_csv(readings: &[Co2Row]) -> String {
    let mut csv = String::from("#,CO2_PPM,TEMP_C,HUMIDITY_PCT,TIME\n");
    for r in readings {
        csv.push_str(&format!("{},{},{},{},{}\n", r.row, r.co2_ppm, r.temperature, r.humidity, r.time));
    }
    csv
}

pub fn build_temperature_humidity_csv(readings: &[TemperatureHumidityRow]) -> String {
    if readings.is_empty() {
        return String::from("#,TIME\n");
    }
    let sensor_count = readings.first().map(|row| row.sensors.len()).unwrap_or(0);
    let mut csv = String::from("#,");
    for i in 0..sensor_count {
        csv.push_str(&format!("TEMP_{i}_C,RH_{i}_PCT,"));
    }
    csv.push_str("TIME\n");
    for row in readings {
        csv.push_str(&format!("{},", row.row));
        for sensor in &row.sensors {
            if sensor.read_ok {
                csv.push_str(&format!("{},{},", sensor.temperature_celsius, sensor.relative_humidity_percent));
            } else {
                csv.push_str(",,");
            }
        }
        csv.push_str(&format!("{}\n", row.time));
    }
    csv
}

pub fn build_voltage_csv(readings: &[VoltageRow]) -> String {
    let mut csv = String::from("#,CH0_V,CH1_V,CH2_V,CH3_V,TIME\n");
    for row in readings {
        csv.push_str(&format!("{},", row.row));
        for (i, voltage) in row.channels.iter().enumerate() {
            csv.push_str(&format!("{voltage:.4}"));
            if i < row.channels.len() - 1 {
                csv.push(',');
            }
        }
        csv.push_str(&format!(",{}\n", row.time));
    }
    csv
}
