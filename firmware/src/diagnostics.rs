use alloc::string::String;
use alloc::vec::Vec;
use core::ffi::c_char;
use core::sync::atomic::{AtomicU32, Ordering};

pub static MQTT_RECONNECT_COUNT: AtomicU32 = AtomicU32::new(0);
pub static WIFI_RECONNECT_COUNT: AtomicU32 = AtomicU32::new(0);
pub static PUBLISH_SUCCESS_COUNT: AtomicU32 = AtomicU32::new(0);
pub static BOOT_EPOCH_SECONDS: AtomicU32 = AtomicU32::new(0);

unsafe extern "C" {
    fn diagnostics_get_reset_cause(out: *mut c_char, out_size: usize) -> i32;
    fn diagnostics_get_heap_min_free() -> u32;
    fn diagnostics_get_heap_total() -> u32;
    fn diagnostics_increment_boot_count() -> u32;
    fn diagnostics_get_wifi_ssid(out: *mut c_char, out_size: usize) -> i32;
    fn diagnostics_get_wifi_bssid(out: *mut c_char, out_size: usize) -> i32;
    fn diagnostics_get_wifi_channel() -> u8;
    fn diagnostics_get_wifi_link_mode_string(out: *mut c_char, out_size: usize) -> i32;
    fn diagnostics_get_cpu_temperature_milli_c() -> i32;
    fn diagnostics_get_storage_free_bytes() -> u32;
    fn prometheus_get_publish_failures() -> u32;
}

pub fn heap_min_free() -> u32 {
    unsafe { diagnostics_get_heap_min_free() }
}

pub fn heap_total() -> u32 {
    unsafe { diagnostics_get_heap_total() }
}

pub fn cpu_temperature_milli_c() -> i32 {
    unsafe { diagnostics_get_cpu_temperature_milli_c() }
}

pub fn storage_free_bytes() -> u32 {
    unsafe { diagnostics_get_storage_free_bytes() }
}

pub fn wifi_channel() -> u8 {
    unsafe { diagnostics_get_wifi_channel() }
}

pub fn publish_failures() -> u32 {
    unsafe { prometheus_get_publish_failures() }
}

pub fn increment_boot_count() -> u32 {
    unsafe { diagnostics_increment_boot_count() }
}

fn fill_string(call: unsafe extern "C" fn(*mut c_char, usize) -> i32, capacity: usize) -> String {
    let mut buffer = Vec::<u8>::with_capacity(capacity);
    buffer.resize(capacity, 0);
    let result = unsafe { call(buffer.as_mut_ptr() as *mut c_char, capacity) };
    if result != 0 {
        return String::new();
    }
    let length = buffer.iter().position(|&b| b == 0).unwrap_or(0);
    String::from_utf8_lossy(&buffer[..length]).into_owned()
}

pub fn reset_cause() -> String {
    fill_string(diagnostics_get_reset_cause, 32)
}

pub fn wifi_ssid() -> String {
    fill_string(diagnostics_get_wifi_ssid, 33)
}

pub fn wifi_bssid() -> String {
    fill_string(diagnostics_get_wifi_bssid, 18)
}

pub fn wifi_link_mode() -> String {
    fill_string(diagnostics_get_wifi_link_mode_string, 16)
}

pub fn last_boot_iso() -> String {
    let boot_epoch = BOOT_EPOCH_SECONDS.load(Ordering::Relaxed);
    if boot_epoch == 0 {
        return String::new();
    }
    crate::cloudevents::epoch_to_rfc3339(boot_epoch as i64)
}
