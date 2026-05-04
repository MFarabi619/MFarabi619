use alloc::format;
use alloc::string::String;
use core::sync::atomic::Ordering;
use log_04::info;
use zephyr::raw::*;

use crate::cloudevents;
use crate::diagnostics;
use crate::mqtt;
use crate::sensors;

unsafe extern "C" {
    fn mqtt_helper_get_wifi_rssi() -> i32;
    fn mqtt_helper_get_heap_free() -> u32;
    fn mqtt_helper_get_epoch_seconds() -> i64;
    fn mqtt_helper_get_ipv4(out: *mut u8, out_size: usize);
    fn sdcard_is_mounted() -> bool;
    fn prometheus_increment_publish_failures();
}

fn ipv4_address() -> String {
    let mut buffer = [0u8; 16];
    unsafe { mqtt_helper_get_ipv4(buffer.as_mut_ptr(), buffer.len()) };
    let length = buffer.iter().position(|&b| b == 0).unwrap_or(0);
    String::from_utf8_lossy(&buffer[..length]).into_owned()
}

fn json_escape(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for character in input.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out
}

fn publish_event(topic: &str, event_type: &str, source: &str, data: &str) {
    let ts = unsafe { mqtt_helper_get_epoch_seconds() };
    let envelope = cloudevents::envelope(event_type, source, ts, data);
    if mqtt::publish(topic, envelope.as_bytes(), true).is_err() {
        unsafe { prometheus_increment_publish_failures() };
    } else {
        diagnostics::PUBLISH_SUCCESS_COUNT.fetch_add(1, Ordering::Relaxed);
    }
}

fn source_uri(host: &str) -> String {
    format!("ceratina/{}", host)
}

pub fn publish_soil() {
    let host = crate::utils::hostname();
    let source = source_uri(host);

    for (index, probe) in sensors::soil_probes().iter().enumerate() {
        let Some(reading) = sensors::read_soil(probe.device) else {
            continue;
        };

        let mut data = format!(
            r#"{{"instance_index":{},"slave_id":{},"temperature_celsius":{:.1},"moisture_percent":{:.1}"#,
            index,
            reading.slave_id,
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

        data.push('}');

        let topic = format!("ceratina/{}/soil/{}/state", host, index);
        publish_event(&topic, "sensors.soil.v1", &source, &data);
    }
}

pub fn publish_air_quality() {
    let host = crate::utils::hostname();
    let source = source_uri(host);

    let device = sensors::co2_device();
    let Some(reading) = sensors::read_scd41(device) else {
        return;
    };

    let data = format!(
        r#"{{"co2_ppm":{},"temperature_celsius":{:.1},"humidity_percent":{:.1}}}"#,
        reading.co2_ppm, reading.temperature_celsius, reading.humidity_percent,
    );

    let topic = format!("ceratina/{}/air_quality/state", host);
    publish_event(&topic, "sensors.air_quality.v1", &source, &data);
}

pub fn publish_status() {
    let host = crate::utils::hostname();
    let rssi = unsafe { mqtt_helper_get_wifi_rssi() };
    let memory_heap_free = unsafe { mqtt_helper_get_heap_free() };
    let memory_heap_min_free = diagnostics::heap_min_free();
    let memory_heap_total = diagnostics::heap_total();
    let uptime_seconds = unsafe { k_uptime_get() / 1000 };
    let sd_mounted = unsafe { sdcard_is_mounted() };

    let reset_cause = json_escape(&diagnostics::reset_cause());
    let boot_count = diagnostics::increment_boot_count();
    let publish_success_total = diagnostics::PUBLISH_SUCCESS_COUNT.load(Ordering::Relaxed);
    let publish_failures_total = diagnostics::publish_failures();
    let mqtt_reconnects_total = diagnostics::MQTT_RECONNECT_COUNT.load(Ordering::Relaxed);
    let wifi_reconnects_total = diagnostics::WIFI_RECONNECT_COUNT.load(Ordering::Relaxed);

    let wifi_ssid = json_escape(&diagnostics::wifi_ssid());
    let wifi_bssid = json_escape(&diagnostics::wifi_bssid());
    let wifi_channel = diagnostics::wifi_channel();
    let wifi_link_mode = json_escape(&diagnostics::wifi_link_mode());
    let ip_address = json_escape(&ipv4_address());

    let storage_free_bytes = diagnostics::storage_free_bytes();
    let cpu_temperature_milli_c = diagnostics::cpu_temperature_milli_c();
    let last_boot_iso = json_escape(&diagnostics::last_boot_iso());

    let mut data = String::with_capacity(640);
    data.push('{');
    data.push_str(&format!(r#""wifi_rssi":{}"#, rssi));
    data.push_str(&format!(r#","memory_heap_free":{}"#, memory_heap_free));
    data.push_str(&format!(r#","memory_heap_min_free":{}"#, memory_heap_min_free));
    data.push_str(&format!(r#","memory_heap_total":{}"#, memory_heap_total));
    data.push_str(&format!(r#","uptime_seconds":{}"#, uptime_seconds));
    data.push_str(&format!(
        r#","sd_mounted":{}"#,
        if sd_mounted { "true" } else { "false" }
    ));
    data.push_str(&format!(r#","reset_cause":"{}""#, reset_cause));
    data.push_str(&format!(r#","boot_count":{}"#, boot_count));
    data.push_str(&format!(r#","publish_success_total":{}"#, publish_success_total));
    data.push_str(&format!(r#","publish_failures_total":{}"#, publish_failures_total));
    data.push_str(&format!(r#","mqtt_reconnects_total":{}"#, mqtt_reconnects_total));
    data.push_str(&format!(r#","wifi_reconnects_total":{}"#, wifi_reconnects_total));
    data.push_str(&format!(r#","wifi_ssid":"{}""#, wifi_ssid));
    data.push_str(&format!(r#","wifi_bssid":"{}""#, wifi_bssid));
    data.push_str(&format!(r#","wifi_channel":{}"#, wifi_channel));
    data.push_str(&format!(r#","wifi_link_mode":"{}""#, wifi_link_mode));
    data.push_str(&format!(r#","ip_address":"{}""#, ip_address));
    data.push_str(&format!(r#","storage_free_bytes":{}"#, storage_free_bytes));
    data.push_str(&format!(r#","cpu_temperature_milli_c":{}"#, cpu_temperature_milli_c));
    if !last_boot_iso.is_empty() {
        data.push_str(&format!(r#","last_boot_iso":"{}""#, last_boot_iso));
    }
    data.push('}');

    let topic = format!("ceratina/{}/status/state", host);
    publish_event(&topic, "status.v1", &source_uri(host), &data);
}

pub fn publish_firmware_info() {
    let host = crate::utils::hostname();
    let topic = format!("ceratina/{}/firmware/info", host);
    let payload = format!(
        r#"{{"installed_version":"{}","build_target":"esp32s3"}}"#,
        crate::home_assistant::FIRMWARE_VERSION,
    );
    publish_tracked_raw(&topic, payload.as_bytes());
}

pub fn publish_update_state() {
    let host = crate::utils::hostname();
    let topic = format!("ceratina/{}/firmware/state", host);
    let payload = format!(
        r#"{{"installed_version":"{}","latest_version":"{}"}}"#,
        crate::home_assistant::FIRMWARE_VERSION,
        crate::home_assistant::FIRMWARE_VERSION,
    );
    publish_tracked_raw(&topic, payload.as_bytes());
}

fn publish_tracked_raw(topic: &str, payload: &[u8]) {
    if mqtt::publish(topic, payload, true).is_err() {
        unsafe { prometheus_increment_publish_failures() };
    }
}

pub fn publish_led_state() {
    let host = crate::utils::hostname();
    let state = if crate::led::is_on() { "ON" } else { "OFF" };
    let topic = format!("ceratina/{}/led/state", host);
    publish_tracked_raw(&topic, state.as_bytes());

    let color = crate::led::current_color();
    let payload = format!("{},{},{}", color.0, color.1, color.2);
    let topic = format!("ceratina/{}/led/color", host);
    publish_tracked_raw(&topic, payload.as_bytes());
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
    publish_soil();
    publish_air_quality();
    publish_status();
    publish_led_state();
    info!("Published all sensor state to MQTT");
}
