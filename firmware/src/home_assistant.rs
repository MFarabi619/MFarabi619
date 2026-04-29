use alloc::format;
use alloc::string::String;
use log_04::info;

use crate::mqtt;
use crate::sensors;

unsafe extern "C" {
    fn mqtt_helper_get_mac(out: *mut u8);
    fn mqtt_helper_get_chip_revision() -> u32;
    fn mqtt_helper_get_ipv4(out: *mut u8, out_size: usize);
}

fn mac_address() -> [u8; 6] {
    let mut mac = [0u8; 6];
    unsafe { mqtt_helper_get_mac(mac.as_mut_ptr()) };
    mac
}

fn mac_string(mac: &[u8; 6]) -> String {
    format!(
        "{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]
    )
}

fn mac_colon_string(mac: &[u8; 6]) -> String {
    format!(
        "{:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}",
        mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]
    )
}

fn ipv4_address() -> String {
    let mut buffer = [0u8; 16];
    unsafe { mqtt_helper_get_ipv4(buffer.as_mut_ptr(), buffer.len()) };
    let length = buffer.iter().position(|&b| b == 0).unwrap_or(0);
    String::from_utf8_lossy(&buffer[..length]).into_owned()
}

fn chip_revision() -> u32 {
    unsafe { mqtt_helper_get_chip_revision() }
}

const FIRMWARE_VERSION: &str = "0.1.0";
const EXPIRE_AFTER: u32 = 120;

fn device_block(host: &str, mac: &str, mac_colon: &str, ip: &str) -> String {
    let config_url = if ip.is_empty() {
        String::new()
    } else {
        format!(r#","cu":"http://{}""#, ip)
    };

    format!(
        r#""dev":{{"ids":["ceratina_{}"],"cns":[["mac","{}"]],"name":"ceratina_{}","mf":"Apidae Systems","mdl":"ESP32-S3","sw":"{}","hw":"rev{}"{}}}"#,
        mac, mac_colon, host, FIRMWARE_VERSION, chip_revision(), config_url,
    )
}

fn publish_sensor(
    host: &str,
    device: &str,
    availability_topic: &str,
    sensor_id: &str,
    name: &str,
    device_class: Option<&str>,
    unit: Option<&str>,
    state_topic: &str,
    value_template: &str,
    precision: Option<u8>,
    entity_category: Option<&str>,
) {
    let dc = device_class
        .map(|dc| format!(r#","device_class":"{}""#, dc))
        .unwrap_or_default();
    let u = unit
        .map(|u| format!(r#","unit_of_measurement":"{}""#, u))
        .unwrap_or_default();
    let p = precision
        .map(|p| format!(r#","suggested_display_precision":{}"#, p))
        .unwrap_or_default();
    let ec = entity_category
        .map(|c| format!(r#","entity_category":"{}""#, c))
        .unwrap_or_default();

    let payload = format!(
        r#"{{{},"unique_id":"{}_{}","name":"{}","state_class":"measurement"{}{}{}{},"state_topic":"{}","value_template":"{}","availability_topic":"{}","expire_after":{}}}"#,
        device, host, sensor_id, name,
        dc, u, p, ec,
        state_topic, value_template, availability_topic, EXPIRE_AFTER,
    );

    let topic = format!("homeassistant/sensor/{}_{}/config", host, sensor_id);
    if mqtt::publish(&topic, payload.as_bytes(), true).is_err() {
        info!("Failed to publish discovery for {}", sensor_id);
    }
}

fn publish_button(
    host: &str,
    device: &str,
    availability_topic: &str,
    button_id: &str,
    name: &str,
    device_class: Option<&str>,
    command_topic: &str,
) {
    let dc = device_class
        .map(|dc| format!(r#","device_class":"{}""#, dc))
        .unwrap_or_default();

    let payload = format!(
        r#"{{{},"unique_id":"{}_{}","name":"{}"{}{}}}"#,
        device, host, button_id, name, dc,
        format_args!(r#","command_topic":"{}","availability_topic":"{}""#,
            command_topic, availability_topic),
    );

    let topic = format!("homeassistant/button/{}_{}/config", host, button_id);
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);
}

fn publish_number(
    host: &str,
    device: &str,
    availability_topic: &str,
    number_id: &str,
    name: &str,
    command_topic: &str,
    state_topic: &str,
    min: u32,
    max: u32,
    step: u32,
    unit: &str,
    entity_category: Option<&str>,
) {
    let ec = entity_category
        .map(|c| format!(r#","entity_category":"{}""#, c))
        .unwrap_or_default();

    let payload = format!(
        r#"{{{},"unique_id":"{}_{}","name":"{}","command_topic":"{}","state_topic":"{}","min":{},"max":{},"step":{},"unit_of_measurement":"{}"{}{}}}"#,
        device, host, number_id, name,
        command_topic, state_topic, min, max, step, unit, ec,
        format_args!(r#","availability_topic":"{}""#, availability_topic),
    );

    let topic = format!("homeassistant/number/{}_{}/config", host, number_id);
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);
}

fn publish_switch(
    host: &str,
    device: &str,
    availability_topic: &str,
    switch_id: &str,
    name: &str,
    command_topic: &str,
    state_topic: &str,
    entity_category: Option<&str>,
) {
    let ec = entity_category
        .map(|c| format!(r#","entity_category":"{}""#, c))
        .unwrap_or_default();

    let payload = format!(
        r#"{{{},"unique_id":"{}_{}","name":"{}","command_topic":"{}","state_topic":"{}"{}{}}}"#,
        device, host, switch_id, name,
        command_topic, state_topic, ec,
        format_args!(r#","availability_topic":"{}""#, availability_topic),
    );

    let topic = format!("homeassistant/switch/{}_{}/config", host, switch_id);
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);
}

fn publish_binary_sensor(
    host: &str,
    device: &str,
    availability_topic: &str,
    sensor_id: &str,
    name: &str,
    device_class: Option<&str>,
    state_topic: &str,
    value_template: &str,
    entity_category: Option<&str>,
) {
    let dc = device_class
        .map(|dc| format!(r#","device_class":"{}""#, dc))
        .unwrap_or_default();
    let ec = entity_category
        .map(|c| format!(r#","entity_category":"{}""#, c))
        .unwrap_or_default();

    let payload = format!(
        r#"{{{},"unique_id":"{}_{}","name":"{}"{}{}{}}}"#,
        device, host, sensor_id, name, dc, ec,
        format_args!(
            r#","state_topic":"{}","value_template":"{}","payload_on":"true","payload_off":"false","availability_topic":"{}""#,
            state_topic, value_template, availability_topic,
        ),
    );

    let topic = format!("homeassistant/binary_sensor/{}_{}/config", host, sensor_id);
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);
}

pub fn publish_discovery_configs() {
    let host = crate::utils::hostname();
    let mac = mac_address();
    let mac_hex = mac_string(&mac);
    let mac_colon = mac_colon_string(&mac);
    let ip = ipv4_address();
    let availability = format!("ceratina/{}/availability", host);
    let device = device_block(host, &mac_hex, &mac_colon, &ip);

    publish_sensor(host, &device, &availability,
        "wind_speed", "Wind Speed",
        Some("wind_speed"), Some("km/h"),
        &format!("ceratina/{}/wind/state", host),
        "{{ value_json.kilometers_per_hour }}",
        Some(1), None);

    publish_sensor(host, &device, &availability,
        "wind_direction", "Wind Direction",
        None, Some("°"),
        &format!("ceratina/{}/wind/state", host),
        "{{ value_json.degrees }}",
        Some(0), None);

    publish_sensor(host, &device, &availability,
        "rainfall", "Rainfall",
        Some("precipitation"), Some("mm"),
        &format!("ceratina/{}/rainfall/state", host),
        "{{ value_json.millimeters }}",
        Some(1), None);

    for device_ptr in sensors::soil_devices() {
        if device_ptr.is_null() {
            continue;
        }
        let count = sensors::soil_probe_count(device_ptr);
        for index in 0..count {
            if let Some(reading) = sensors::read_soil(device_ptr, index) {
                let slave = reading.slave_id;
                let state_topic = format!("ceratina/{}/soil/{}/state", host, slave);

                publish_sensor(host, &device, &availability,
                    &format!("soil_{}_temperature", slave), "Soil Temperature",
                    Some("temperature"), Some("°C"),
                    &state_topic, "{{ value_json.temperature_celsius }}",
                    Some(1), None);

                publish_sensor(host, &device, &availability,
                    &format!("soil_{}_moisture", slave), "Soil Moisture",
                    Some("moisture"), Some("%"),
                    &state_topic, "{{ value_json.moisture_percent }}",
                    Some(1), None);

                if reading.conductivity.is_some() {
                    publish_sensor(host, &device, &availability,
                        &format!("soil_{}_conductivity", slave), "Soil Electrical Conductivity",
                        None, Some("µS/cm"),
                        &state_topic, "{{ value_json.conductivity }}",
                        Some(0), None);
                }

                if reading.salinity.is_some() {
                    publish_sensor(host, &device, &availability,
                        &format!("soil_{}_salinity", slave), "Soil Salinity",
                        None, Some("mg/L"),
                        &state_topic, "{{ value_json.salinity }}",
                        Some(0), None);
                }

                if reading.tds.is_some() {
                    publish_sensor(host, &device, &availability,
                        &format!("soil_{}_tds", slave), "Soil TDS",
                        None, Some("ppm"),
                        &state_topic, "{{ value_json.tds }}",
                        Some(0), None);
                }

                if reading.ph.is_some() {
                    publish_sensor(host, &device, &availability,
                        &format!("soil_{}_ph", slave), "Soil pH",
                        None, None,
                        &state_topic, "{{ value_json.ph }}",
                        Some(1), None);
                }
            }
        }
    }

    let status_topic = format!("ceratina/{}/status/state", host);

    publish_sensor(host, &device, &availability,
        "wifi_rssi", "WiFi RSSI",
        Some("signal_strength"), Some("dBm"),
        &status_topic, "{{ value_json.rssi }}",
        Some(0), Some("diagnostic"));

    publish_sensor(host, &device, &availability,
        "heap_free", "Heap Free",
        None, Some("bytes"),
        &status_topic, "{{ value_json.heap_free }}",
        Some(0), Some("diagnostic"));

    publish_sensor(host, &device, &availability,
        "uptime", "Uptime",
        Some("duration"), Some("s"),
        &status_topic, "{{ value_json.uptime_seconds }}",
        Some(0), Some("diagnostic"));

    publish_binary_sensor(host, &device, &availability,
        "sd_mounted", "SD Card",
        Some("connectivity"),
        &status_topic, "{{ value_json.sd_mounted }}",
        Some("diagnostic"));

    publish_button(host, &device, &availability,
        "reboot", "Reboot", Some("restart"),
        &format!("ceratina/{}/command/reboot", host));

    publish_button(host, &device, &availability,
        "clear_rainfall", "Clear Rainfall", None,
        &format!("ceratina/{}/command/clear_rainfall", host));

    publish_button(host, &device, &availability,
        "force_publish", "Force Publish", None,
        &format!("ceratina/{}/command/force_publish", host));

    publish_number(host, &device, &availability,
        "publish_interval", "Publish Interval",
        &format!("ceratina/{}/config/publish_interval/set", host),
        &format!("ceratina/{}/config/publish_interval", host),
        5, 3600, 5, "s", Some("config"));

    publish_number(host, &device, &availability,
        "sleep_duration", "Sleep Duration",
        &format!("ceratina/{}/config/sleep_duration/set", host),
        &format!("ceratina/{}/config/sleep_duration", host),
        0, 86400, 60, "s", Some("config"));

    publish_switch(host, &device, &availability,
        "deep_sleep", "Deep Sleep",
        &format!("ceratina/{}/config/deep_sleep/set", host),
        &format!("ceratina/{}/config/deep_sleep", host),
        Some("config"));

    info!("Home Assistant discovery configs published");
}
