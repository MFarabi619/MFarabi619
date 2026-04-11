use dioxus::prelude::*;

#[derive(Clone, Copy, PartialEq)]
pub struct FlashDeviceState {
    pub is_connected: Signal<bool>,
    pub connecting: Signal<bool>,
    pub monitor_active: Signal<bool>,
    pub device_lost: Signal<bool>,
}

impl FlashDeviceState {
    pub fn new() -> Self {
        Self {
            is_connected: use_signal(|| false),
            connecting: use_signal(|| false),
            monitor_active: use_signal(|| false),
            device_lost: use_signal(|| false),
        }
    }
}

#[derive(Clone, Copy, PartialEq)]
pub struct FlashChipInfo {
    pub chip_name: Signal<String>,
    pub chip_description: Signal<String>,
    pub chip_features: Signal<Vec<String>>,
    pub chip_mac: Signal<String>,
    pub chip_flash_sizes: Signal<Vec<String>>,
    pub chip_flash_freqs: Signal<Vec<String>>,
    pub bootloader_offset: Signal<u32>,
}

impl FlashChipInfo {
    pub fn new() -> Self {
        Self {
            chip_name: use_signal(String::new),
            chip_description: use_signal(String::new),
            chip_features: use_signal(Vec::new),
            chip_mac: use_signal(String::new),
            chip_flash_sizes: use_signal(Vec::new),
            chip_flash_freqs: use_signal(Vec::new),
            bootloader_offset: use_signal(|| 0u32),
        }
    }

    pub fn clear(&mut self) {
        self.chip_name.set(String::new());
        self.chip_description.set(String::new());
        self.chip_features.set(Vec::new());
        self.chip_mac.set(String::new());
        self.chip_flash_sizes.set(Vec::new());
        self.chip_flash_freqs.set(Vec::new());
        self.bootloader_offset.set(0);
    }
}

#[derive(Clone, Copy, PartialEq)]
pub struct FlashFirmwareState {
    pub firmware_name: Signal<String>,
    pub firmware_size: Signal<usize>,
    pub bundled_selection: Signal<String>,
    pub flashing: Signal<bool>,
    pub progress: Signal<u8>,
}

impl FlashFirmwareState {
    pub fn new() -> Self {
        Self {
            firmware_name: use_signal(String::new),
            firmware_size: use_signal(|| 0usize),
            bundled_selection: use_signal(String::new),
            flashing: use_signal(|| false),
            progress: use_signal(|| 0u8),
        }
    }

    pub fn clear(&mut self) {
        self.firmware_name.set(String::new());
        self.firmware_size.set(0);
        self.bundled_selection.set(String::new());
        self.flashing.set(false);
        self.progress.set(0);
    }
}

#[derive(Clone, Copy, PartialEq)]
pub struct FlashConfig {
    pub baud: Signal<String>,
    pub mode: Signal<String>,
    pub freq: Signal<String>,
    pub size: Signal<String>,
    pub address: Signal<String>,
    pub compress: Signal<bool>,
    pub erase_first: Signal<bool>,
    pub wifi_ssid: Signal<String>,
    pub wifi_pass: Signal<String>,
}

impl FlashConfig {
    pub fn new() -> Self {
        Self {
            baud: use_signal(|| "921600".to_string()),
            mode: use_signal(|| "keep".to_string()),
            freq: use_signal(|| "keep".to_string()),
            size: use_signal(|| "detect".to_string()),
            address: use_signal(|| "0x10000".to_string()),
            compress: use_signal(|| true),
            erase_first: use_signal(|| false),
            wifi_ssid: use_signal(String::new),
            wifi_pass: use_signal(String::new),
        }
    }
}
