use alloc::format;
use log_04::info;
use zephyr::raw::*;

use crate::mqtt;
use crate::sensors;

unsafe extern "C" {
    fn mqtt_helper_get_wifi_rssi() -> i32;
    fn mqtt_helper_get_heap_free() -> u32;
    fn sdcard_is_mounted() -> bool;
}

pub fn publish_wind() {
    let host = crate::utils::hostname();

    if let Some(speed) = sensors::read_wind_speed() {
        let direction = sensors::read_wind_direction();

        let payload = if let Some(direction) = direction {
            format!(
                r#"{{"kilometers_per_hour":{:.1},"degrees":{:.1},"slice":{}}}"#,
                speed.wind_speed_kilometers_per_hour,
                direction.wind_direction_degrees,
                direction.wind_direction_angle_slice,
            )
        } else {
            format!(
                r#"{{"kilometers_per_hour":{:.1}}}"#,
                speed.wind_speed_kilometers_per_hour,
            )
        };

        let topic = format!("ceratina/{}/wind/state", host);
        let _ = mqtt::publish(&topic, payload.as_bytes(), true);
    }
}

pub fn publish_rainfall() {
    let host = crate::utils::hostname();

    if let Some(reading) = sensors::read_rainfall() {
        let payload = format!(
            r#"{{"millimeters":{:.1}}}"#,
            reading.rainfall_millimeters,
        );
        let topic = format!("ceratina/{}/rainfall/state", host);
        let _ = mqtt::publish(&topic, payload.as_bytes(), true);
    }
}

pub fn publish_soil() {
    let host = crate::utils::hostname();

    for device in sensors::soil_devices() {
        if device.is_null() {
            continue;
        }
        let count = sensors::soil_probe_count(device);
        for index in 0..count {
            if let Some(reading) = sensors::read_soil(device, index) {
                let mut payload = format!(
                    r#"{{"temperature_celsius":{:.1},"moisture_percent":{:.1}"#,
                    reading.temperature_celsius,
                    reading.moisture_percent,
                );

                if let Some(conductivity) = reading.conductivity {
                    payload.push_str(&format!(r#","conductivity":{}"#, conductivity));
                }
                if let Some(salinity) = reading.salinity {
                    payload.push_str(&format!(r#","salinity":{}"#, salinity));
                }
                if let Some(tds) = reading.tds {
                    payload.push_str(&format!(r#","tds":{}"#, tds));
                }
                if let Some(ph) = reading.ph {
                    payload.push_str(&format!(r#","ph":{:.1}"#, ph));
                }

                payload.push('}');

                let topic = format!("ceratina/{}/soil/{}/state", host, reading.slave_id);
                let _ = mqtt::publish(&topic, payload.as_bytes(), true);
            }
        }
    }
}

pub fn publish_status() {
    let host = crate::utils::hostname();
    let rssi = unsafe { mqtt_helper_get_wifi_rssi() };
    let heap_free = unsafe { mqtt_helper_get_heap_free() };
    let uptime_seconds = unsafe { k_uptime_get() / 1000 };
    let sd_mounted = unsafe { sdcard_is_mounted() };

    let payload = format!(
        r#"{{"rssi":{},"heap_free":{},"uptime_seconds":{},"sd_mounted":{}}}"#,
        rssi, heap_free, uptime_seconds,
        if sd_mounted { "true" } else { "false" },
    );

    let topic = format!("ceratina/{}/status/state", host);
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);
}

pub fn publish_config_state() {
    let host = crate::utils::hostname();
    let interval = mqtt::publish_interval();
    let deep_sleep_enabled = mqtt::deep_sleep_enabled();
    let sleep_duration = mqtt::sleep_duration();

    let topic = format!("ceratina/{}/config/publish_interval", host);
    let payload = format!("{}", interval);
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);

    let topic = format!("ceratina/{}/config/deep_sleep", host);
    let payload = if deep_sleep_enabled { "ON" } else { "OFF" };
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);

    let topic = format!("ceratina/{}/config/sleep_duration", host);
    let payload = format!("{}", sleep_duration);
    let _ = mqtt::publish(&topic, payload.as_bytes(), true);
}

pub fn publish_all() {
    publish_wind();
    publish_rainfall();
    publish_soil();
    publish_status();
    info!("Published all sensor state to MQTT");
}
