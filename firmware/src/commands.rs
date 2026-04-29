use alloc::format;
use log_04::info;

use crate::home_assistant;
use crate::mqtt;
use crate::publish;
use crate::sensors;

unsafe extern "C" {
    fn sys_reboot(type_: core::ffi::c_int);
}

fn strip_prefix<'a>(topic: &'a str) -> Option<&'a str> {
    let host = crate::utils::hostname();
    let prefix = format!("ceratina/{}/", host);
    topic.strip_prefix(&prefix)
}

fn parse_u32(payload: &[u8]) -> Option<u32> {
    core::str::from_utf8(payload)
        .ok()
        .and_then(|text| text.trim().parse().ok())
}

pub fn handle_command(topic: &str, payload: &[u8]) {
    if topic == "homeassistant/status" {
        let text = core::str::from_utf8(payload).unwrap_or("");
        if text.trim() == "online" {
            info!("Home Assistant came online, re-publishing discovery");
            home_assistant::publish_discovery_configs();
            publish::publish_config_state();
            publish::publish_all();
        }
        return;
    }

    let Some(suffix) = strip_prefix(topic) else {
        info!("Unknown topic prefix: {}", topic);
        return;
    };

    match suffix {
        "command/reboot" => {
            info!("Reboot command received");
            unsafe { sys_reboot(0) };
        }
        "command/clear_rainfall" => {
            info!("Clear rainfall command received");
            sensors::clear_rainfall();
            publish::publish_rainfall();
        }
        "command/force_publish" => {
            info!("Force publish command received");
            publish::publish_all();
        }
        "config/publish_interval/set" => {
            if let Some(seconds) = parse_u32(payload) {
                let clamped = seconds.clamp(5, 3600);
                info!("Setting publish interval to {}s", clamped);
                mqtt::set_publish_interval(clamped);
                publish::publish_config_state();
            }
        }
        "config/sleep_duration/set" => {
            if let Some(seconds) = parse_u32(payload) {
                let clamped = seconds.clamp(0, 86400);
                info!("Setting sleep duration to {}s", clamped);
                mqtt::set_sleep_duration(clamped);
                publish::publish_config_state();
            }
        }
        "config/deep_sleep/set" => {
            let text = core::str::from_utf8(payload).unwrap_or("");
            let enabled = text.trim() == "ON";
            info!("Setting deep sleep: {}", if enabled { "ON" } else { "OFF" });
            mqtt::set_deep_sleep_enabled(enabled);
            publish::publish_config_state();
        }
        _ => {
            info!("Unknown command suffix: {}", suffix);
        }
    }
}
