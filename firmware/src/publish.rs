use alloc::format;
use alloc::string::String;
use log_04::info;
use zephyr::raw::*;

use crate::cloudevents;
use crate::mqtt;
use crate::sensors;

unsafe extern "C" {
    fn mqtt_helper_get_wifi_rssi() -> i32;
    fn mqtt_helper_get_heap_free() -> u32;
    fn mqtt_helper_get_epoch_seconds() -> i64;
    fn sdcard_is_mounted() -> bool;
    fn prometheus_increment_publish_failures();
}

fn publish_event(topic: &str, event_type: &str, source: &str, data: &str) {
    let ts = unsafe { mqtt_helper_get_epoch_seconds() };
    let envelope = cloudevents::envelope(event_type, source, ts, data);
    if mqtt::publish(topic, envelope.as_bytes(), true).is_err() {
        unsafe { prometheus_increment_publish_failures() };
    }
}

fn source_uri(host: &str) -> String {
    format!("ceratina/{}", host)
}

pub fn publish_wind_speed() {
    let host = crate::utils::hostname();
    if let Some(speed) = sensors::read_wind_speed() {
        let data = format!(
            r#"{{"wind_speed_kilometers_per_hour":{:.1}}}"#,
            speed.wind_speed_kilometers_per_hour,
        );
        let topic = format!("ceratina/{}/wind_speed/state", host);
        publish_event(&topic, "sensors.wind_speed.v1", &source_uri(host), &data);
    }
}

pub fn publish_wind_direction() {
    let host = crate::utils::hostname();
    if let Some(direction) = sensors::read_wind_direction() {
        let data = format!(
            r#"{{"wind_direction_angle":{:.1},"wind_direction_slice":{}}}"#,
            direction.wind_direction_degrees,
            direction.wind_direction_angle_slice,
        );
        let topic = format!("ceratina/{}/wind_direction/state", host);
        publish_event(&topic, "sensors.wind_direction.v1", &source_uri(host), &data);
    }
}

pub fn publish_rainfall() {
    let host = crate::utils::hostname();
    if let Some(reading) = sensors::read_rainfall() {
        let data = format!(
            r#"{{"rainfall_millimeters":{:.1}}}"#,
            reading.rainfall_millimeters,
        );
        let topic = format!("ceratina/{}/rainfall/state", host);
        publish_event(&topic, "sensors.rainfall.v1", &source_uri(host), &data);
    }
}

pub fn publish_soil() {
    let host = crate::utils::hostname();
    let source = source_uri(host);

    for device in sensors::soil_devices() {
        if device.is_null() {
            continue;
        }
        let count = sensors::soil_probe_count(device);
        for index in 0..count {
            if let Some(reading) = sensors::read_soil(device, index) {
                let mut data = format!(
                    r#"{{"temperature_celsius":{:.1},"moisture_percent":{:.1}"#,
                    reading.temperature_celsius,
                    reading.moisture_percent,
                );

                if let Some(conductivity) = reading.conductivity {
                    data.push_str(&format!(r#","conductivity":{}"#, conductivity));
                }
                if let Some(salinity) = reading.salinity {
                    data.push_str(&format!(r#","salinity":{}"#, salinity));
                }
                if let Some(tds) = reading.tds {
                    data.push_str(&format!(r#","tds":{}"#, tds));
                }
                if let Some(ph) = reading.ph {
                    data.push_str(&format!(r#","ph":{:.1}"#, ph));
                }

                data.push('}');

                let topic = format!("ceratina/{}/soil/{}/state", host, index);
                publish_event(&topic, "sensors.soil.v1", &source, &data);
            }
        }
    }
}

pub fn publish_status() {
    let host = crate::utils::hostname();
    let rssi = unsafe { mqtt_helper_get_wifi_rssi() };
    let memory_heap_free = unsafe { mqtt_helper_get_heap_free() };
    let uptime_seconds = unsafe { k_uptime_get() / 1000 };
    let sd_mounted = unsafe { sdcard_is_mounted() };

    let data = format!(
        r#"{{"wifi_rssi":{},"memory_heap_free":{},"uptime_seconds":{},"sd_mounted":{}}}"#,
        rssi, memory_heap_free, uptime_seconds,
        if sd_mounted { "true" } else { "false" },
    );

    let topic = format!("ceratina/{}/status/state", host);
    publish_event(&topic, "status.v1", &source_uri(host), &data);
}

fn publish_tracked_raw(topic: &str, payload: &[u8]) {
    if mqtt::publish(topic, payload, true).is_err() {
        unsafe { prometheus_increment_publish_failures() };
    }
}

pub fn publish_config_state() {
    let host = crate::utils::hostname();
    let interval = mqtt::publish_interval();
    let deep_sleep_enabled = mqtt::deep_sleep_enabled();
    let sleep_duration = mqtt::sleep_duration();

    let topic = format!("ceratina/{}/config/publish_interval", host);
    let payload = format!("{}", interval);
    publish_tracked_raw(&topic, payload.as_bytes());

    let topic = format!("ceratina/{}/config/deep_sleep", host);
    let payload = if deep_sleep_enabled { "ON" } else { "OFF" };
    publish_tracked_raw(&topic, payload.as_bytes());

    let topic = format!("ceratina/{}/config/sleep_duration", host);
    let payload = format!("{}", sleep_duration);
    publish_tracked_raw(&topic, payload.as_bytes());
}

pub fn publish_all() {
    // Modbus polling disabled — RS-485 bus issue, re-enable once wiring is sorted
    // publish_wind_speed();
    // publish_wind_direction();
    // publish_rainfall();
    // publish_soil();
    publish_status();
    info!("Published all sensor state to MQTT");
}
