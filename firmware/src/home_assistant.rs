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
const SUPPORT_URL: &str = "https://github.com/MFarabi619/MFarabi619";

fn device_block(host: &str, mac_colon: &str, mac_hex: &str, ip: &str, device_id: &str) -> String {
    let config_url = if ip.is_empty() {
        String::new()
    } else {
        format!(r#","cu":"http://{}""#, ip)
    };

    format!(
        r#""dev":{{"ids":["{}"],"cns":[["mac","{}"]],"name":"{}","mf":"Apidae Systems","mdl":"ESP32-S3","sn":"{}","sw":"{}","hw":"rev{}"{}}},"o":{{"name":"ceratina-fw","sw":"{}","url":"{}"}}"#,
        device_id, mac_colon, host, mac_hex, FIRMWARE_VERSION, chip_revision(), config_url,
        FIRMWARE_VERSION, SUPPORT_URL,
    )
}

fn publish_sensor(
    device_id: &str,
    device: &str,
    availability_topic: &str,
    sensor_id: &str,
    name: &str,
    device_class: Option<&str>,
    unit: Option<&str>,
    state_topic: &str,
    value_template: &str,
    state_class: &str,
    precision: Option<u8>,
    entity_category: Option<&str>,
    icon: Option<&str>,
    expire_after: u32,
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
    let ic = icon
        .map(|i| format!(r#","icon":"{}""#, i))
        .unwrap_or_default();

    let payload = format!(
        r#"{{{},"unique_id":"{}_{}","name":"{}","state_class":"{}"{}{}{}{}{},"state_topic":"{}","value_template":"{}","availability_topic":"{}","expire_after":{}}}"#,
        device, device_id, sensor_id, name, state_class,
        dc, u, p, ec, ic,
        state_topic, value_template, availability_topic, expire_after,
    );

    let topic = format!("homeassistant/sensor/{}/{}/config", device_id, sensor_id);
    if mqtt::publish(&topic, payload.as_bytes(), true).is_err() {
        info!("Failed to publish discovery for {}", sensor_id);
    }
}

fn publish_button(
    device_id: &str,
    device: &str,
    availability_topic: &str,
    button_id: &str,
    name: &str,
    device_class: Option<&str>,
    icon: Option<&str>,
    command_topic: &str,
) {
    let dc = device_class
        .map(|dc| format!(r#","device_class":"{}""#, dc))
        .unwrap_or_default();
    let ic = icon
        .map(|i| format!(r#","icon":"{}""#, i))
        .unwrap_or_default();

    let payload = format!(
        r#"{{{},"unique_id":"{}_{}","name":"{}"{}{},"command_topic":"{}","availability_topic":"{}"}}"#,
        device, device_id, button_id, name, dc, ic, command_topic, availability_topic,
    );

    let topic = format!("homeassistant/button/{}/{}/config", device_id, button_id);
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);
}

fn publish_number(
    device_id: &str,
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
        r#"{{{},"unique_id":"{}_{}","name":"{}","command_topic":"{}","state_topic":"{}","min":{},"max":{},"step":{},"unit_of_measurement":"{}"{},"availability_topic":"{}"}}"#,
        device, device_id, number_id, name,
        command_topic, state_topic, min, max, step, unit, ec, availability_topic,
    );

    let topic = format!("homeassistant/number/{}/{}/config", device_id, number_id);
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);
}

fn publish_switch(
    device_id: &str,
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
        r#"{{{},"unique_id":"{}_{}","name":"{}","command_topic":"{}","state_topic":"{}"{},"availability_topic":"{}"}}"#,
        device, device_id, switch_id, name,
        command_topic, state_topic, ec, availability_topic,
    );

    let topic = format!("homeassistant/switch/{}/{}/config", device_id, switch_id);
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);
}

fn publish_binary_sensor(
    device_id: &str,
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
        r#"{{{},"unique_id":"{}_{}","name":"{}"{}{},"state_topic":"{}","value_template":"{}","payload_on":"true","payload_off":"false","availability_topic":"{}"}}"#,
        device, device_id, sensor_id, name, dc, ec,
        state_topic, value_template, availability_topic,
    );

    let topic = format!("homeassistant/binary_sensor/{}/{}/config", device_id, sensor_id);
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);
}

pub fn publish_discovery_configs() {
    let host = crate::utils::hostname();
    let mac = mac_address();
    let mac_hex = mac_string(&mac);
    let mac_colon = mac_colon_string(&mac);
    let ip = ipv4_address();
    let device_id = format!("ceratina_{}", mac_hex);
    let availability = format!("ceratina/{}/availability", host);
    let device = device_block(host, &mac_colon, &mac_hex, &ip, &device_id);
    let expire_after = mqtt::publish_interval().saturating_mul(5) / 2;

    publish_sensor(&device_id, &device, &availability,
        "wind_speed", "Wind Speed",
        Some("wind_speed"), Some("km/h"),
        &format!("ceratina/{}/wind_speed/state", host),
        "{{ value_json.data.wind_speed_kilometers_per_hour }}",
        "measurement", Some(1), None, Some("mdi:weather-windy"), expire_after);

    publish_sensor(&device_id, &device, &availability,
        "wind_direction", "Wind Direction",
        None, Some("°"),
        &format!("ceratina/{}/wind_direction/state", host),
        "{{ value_json.data.wind_direction_angle }}",
        "measurement", Some(0), None, Some("mdi:compass-outline"), expire_after);

    publish_sensor(&device_id, &device, &availability,
        "rainfall", "Rainfall",
        Some("precipitation"), Some("mm"),
        &format!("ceratina/{}/rainfall/state", host),
        "{{ value_json.data.rainfall_millimeters }}",
        "total_increasing", Some(1), None, Some("mdi:weather-pouring"), expire_after);

    for device_ptr in sensors::soil_devices() {
        if device_ptr.is_null() {
            continue;
        }
        let count = sensors::soil_probe_count(device_ptr);
        for index in 0..count {
            let state_topic = format!("ceratina/{}/soil/{}/state", host, index);

            publish_sensor(&device_id, &device, &availability,
                &format!("soil_{}_temperature", index), "Soil Temperature",
                Some("temperature"), Some("°C"),
                &state_topic, "{{ value_json.data.temperature_celsius }}",
                "measurement", Some(1), None, Some("mdi:thermometer"), expire_after);

            publish_sensor(&device_id, &device, &availability,
                &format!("soil_{}_moisture", index), "Soil Moisture",
                Some("moisture"), Some("%"),
                &state_topic, "{{ value_json.data.moisture_percent }}",
                "measurement", Some(1), None, Some("mdi:water-percent"), expire_after);

            publish_sensor(&device_id, &device, &availability,
                &format!("soil_{}_conductivity", index), "Soil Electrical Conductivity",
                None, Some("µS/cm"),
                &state_topic, "{{ value_json.data.conductivity }}",
                "measurement", Some(0), None, Some("mdi:flash-triangle-outline"), expire_after);

            publish_sensor(&device_id, &device, &availability,
                &format!("soil_{}_salinity", index), "Soil Salinity",
                None, Some("mg/L"),
                &state_topic, "{{ value_json.data.salinity }}",
                "measurement", Some(0), None, Some("mdi:shaker-outline"), expire_after);

            publish_sensor(&device_id, &device, &availability,
                &format!("soil_{}_tds", index), "Soil TDS",
                None, Some("ppm"),
                &state_topic, "{{ value_json.data.tds }}",
                "measurement", Some(0), None, Some("mdi:beaker-outline"), expire_after);

            publish_sensor(&device_id, &device, &availability,
                &format!("soil_{}_ph", index), "Soil pH",
                None, None,
                &state_topic, "{{ value_json.data.ph }}",
                "measurement", Some(1), None, Some("mdi:ph"), expire_after);
        }
    }

    let status_topic = format!("ceratina/{}/status/state", host);

    publish_sensor(&device_id, &device, &availability,
        "wifi_rssi", "WiFi RSSI",
        Some("signal_strength"), Some("dBm"),
        &status_topic, "{{ value_json.data.wifi_rssi }}",
        "measurement", Some(0), Some("diagnostic"), Some("mdi:wifi"), expire_after);

    publish_sensor(&device_id, &device, &availability,
        "heap_free", "Heap Free",
        Some("data_size"), Some("B"),
        &status_topic, "{{ value_json.data.memory_heap_free }}",
        "measurement", Some(0), Some("diagnostic"), Some("mdi:memory"), expire_after);

    publish_sensor(&device_id, &device, &availability,
        "uptime", "Uptime",
        Some("duration"), Some("s"),
        &status_topic, "{{ value_json.data.uptime_seconds }}",
        "measurement", Some(0), Some("diagnostic"), Some("mdi:clock-outline"), expire_after);

    publish_binary_sensor(&device_id, &device, &availability,
        "sd_mounted", "SD Card",
        Some("connectivity"),
        &status_topic, "{{ value_json.data.sd_mounted }}",
        Some("diagnostic"));

    publish_button(&device_id, &device, &availability,
        "reboot", "Reboot", Some("restart"), Some("mdi:restart"),
        &format!("ceratina/{}/command/reboot", host));

    publish_button(&device_id, &device, &availability,
        "clear_rainfall", "Clear Rainfall", None, Some("mdi:water-off-outline"),
        &format!("ceratina/{}/command/clear_rainfall", host));

    publish_button(&device_id, &device, &availability,
        "force_publish", "Force Publish", None, Some("mdi:upload-outline"),
        &format!("ceratina/{}/command/force_publish", host));

    publish_number(&device_id, &device, &availability,
        "publish_interval", "Publish Interval",
        &format!("ceratina/{}/config/publish_interval/set", host),
        &format!("ceratina/{}/config/publish_interval", host),
        5, 3600, 5, "s", Some("config"));

    publish_number(&device_id, &device, &availability,
        "sleep_duration", "Sleep Duration",
        &format!("ceratina/{}/config/sleep_duration/set", host),
        &format!("ceratina/{}/config/sleep_duration", host),
        0, 86400, 60, "s", Some("config"));

    publish_switch(&device_id, &device, &availability,
        "deep_sleep", "Deep Sleep",
        &format!("ceratina/{}/config/deep_sleep/set", host),
        &format!("ceratina/{}/config/deep_sleep", host),
        Some("config"));

    info!("Home Assistant discovery configs published");
}
