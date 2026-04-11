use super::{bridge::*, state::*};
use dioxus::prelude::*;
use ui::components::toast::use_toast;

#[derive(Clone, Copy, PartialEq)]
pub struct FlashController {
    pub device: FlashDeviceState,
    pub chip: FlashChipInfo,
    pub firmware: FlashFirmwareState,
    pub config: FlashConfig,
}

impl FlashController {
    pub fn connect(&self) {
        let mut device = self.device;
        let chip = self.chip;
        let mut firmware = self.firmware;
        let baud_val = self.config.baud.read().clone();

        device.connecting.set(true);

        spawn(async move {
            document::eval(JS_INIT_TERMINAL);
            eval_send_and_process(JS_CONNECT, baud_val, device, chip, firmware).await;
            device.connecting.set(false);

            if *device.is_connected.read() {
                firmware.bundled_selection.set("all".to_string());
                restart_monitor(device, chip, firmware).await;
            }
        });
    }

    pub fn disconnect(&self) {
        let mut device = self.device;
        let mut chip = self.chip;
        let mut firmware = self.firmware;

        device.is_connected.set(false);
        device.monitor_active.set(false);
        firmware.clear();
        chip.clear();

        spawn(async move {
            eval_and_process(JS_DISCONNECT, device, chip, firmware).await;
        });
    }

    pub fn flash(&self) {
        let mut device = self.device;
        let mut chip = self.chip;
        let mut firmware = self.firmware;
        let config = self.config;

        firmware.flashing.set(true);
        firmware.progress.set(0);

        let flash_config = serde_json::json!({
            "baud": *config.baud.read(),
            "mode": *config.mode.read(),
            "freq": *config.freq.read(),
            "size": *config.size.read(),
            "addr": *config.address.read(),
            "compress": *config.compress.read(),
            "eraseAll": *config.erase_first.read(),
            "wifiSsid": *config.wifi_ssid.read(),
            "wifiPass": *config.wifi_pass.read(),
        });

        spawn(async move {
            eval_send_and_process(JS_FLASH, flash_config, device, chip, firmware).await;
            firmware.flashing.set(false);
            restart_monitor(device, chip, firmware).await;
        });
    }

    pub fn erase(&self) {
        let mut device = self.device;
        let mut chip = self.chip;
        let mut firmware = self.firmware;
        let baud_val = self.config.baud.read().clone();

        spawn(async move {
            eval_send_and_process(JS_ERASE, baud_val, device, chip, firmware).await;
            restart_monitor(device, chip, firmware).await;
        });
    }

    pub fn reset(&self) {
        let device = self.device;
        let chip = self.chip;
        let firmware = self.firmware;
        let baud_val = self.config.baud.read().clone();

        spawn(async move {
            eval_send_and_process(JS_RESET, baud_val, device, chip, firmware).await;
            restart_monitor(device, chip, firmware).await;
        });
    }

    pub fn toggle_monitor(&self) {
        if *self.device.monitor_active.read() {
            document::eval(JS_MONITOR_STOP);
        } else {
            let device = self.device;
            let chip = self.chip;
            let firmware = self.firmware;
            spawn(async move {
                restart_monitor(device, chip, firmware).await;
            });
        }
    }
}

async fn restart_monitor(
    device: FlashDeviceState,
    chip: FlashChipInfo,
    firmware: FlashFirmwareState,
) {
    eval_send_and_process(JS_MONITOR_START, "115200", device, chip, firmware).await;
}

pub fn use_flash_controller() -> FlashController {
    let mut device = FlashDeviceState::new();
    let mut chip = FlashChipInfo::new();
    let mut firmware = FlashFirmwareState::new();
    let mut config = FlashConfig::new();
    let mut config_loaded = use_signal(|| false);

    let toasts = use_toast();

    // Load config from localStorage on mount
    use_effect(move || {
        let mut config = config;
        spawn(async move {
            let eval = document::eval(
                r#"
                try {
                    const c = JSON.parse(localStorage.getItem('flash_options') || '{}');
                    return JSON.stringify(c);
                } catch(e) { return '{}'; }
            "#,
            );
            if let Ok(json) = eval.await {
                if let Ok(map) =
                    serde_json::from_value::<serde_json::Map<String, serde_json::Value>>(json)
                {
                    if let Some(v) = map.get("baud").and_then(|v| v.as_str()) {
                        config.baud.set(v.to_string());
                    }
                    if let Some(v) = map.get("mode").and_then(|v| v.as_str()) {
                        config.mode.set(v.to_string());
                    }
                    if let Some(v) = map.get("freq").and_then(|v| v.as_str()) {
                        config.freq.set(v.to_string());
                    }
                    if let Some(v) = map.get("size").and_then(|v| v.as_str()) {
                        config.size.set(v.to_string());
                    }
                    if let Some(v) = map.get("addr").and_then(|v| v.as_str()) {
                        config.address.set(v.to_string());
                    }
                    if let Some(v) = map.get("compress").and_then(|v| v.as_bool()) {
                        config.compress.set(v);
                    }
                    if let Some(v) = map.get("eraseAll").and_then(|v| v.as_bool()) {
                        config.erase_first.set(v);
                    }
                }
            }
            config_loaded.set(true);
        });
    });

    use_effect(move || {
        if !*config_loaded.read() {
            return;
        }
        let baud = config.baud.read().clone();
        let mode = config.mode.read().clone();
        let freq = config.freq.read().clone();
        let size = config.size.read().clone();
        let addr = config.address.read().clone();
        let compress = *config.compress.read();
        let erase = *config.erase_first.read();
        let config_json = serde_json::json!({
            "baud": baud,
            "mode": mode,
            "freq": freq,
            "size": size,
            "addr": addr,
            "compress": compress,
            "eraseAll": erase,
        });
        document::eval(&format!(
            "localStorage.setItem('flash_options',{});",
            serde_json::to_string(&config_json).unwrap_or_default()
        ));
    });

    use_effect(move || {
        if *device.device_lost.read() {
            toasts.error("Device disconnected unexpectedly".to_string(), None);
            device.device_lost.set(false);
        }
    });

    use_effect(move || {
        let sel = firmware.bundled_selection.read().clone();
        if sel.is_empty() {
            return;
        }
        let device = device;
        let chip = chip;
        let firmware = firmware;
        spawn(async move {
            eval_send_and_process(JS_FETCH_FIRMWARE, sel, device, chip, firmware).await;
        });
    });

    use_drop(|| {
        document::eval(JS_CLEANUP);
    });

    FlashController {
        device,
        chip,
        firmware,
        config,
    }
}
