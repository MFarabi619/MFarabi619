use core::sync::atomic::AtomicBool;

pub static WIFI_INITIALIZED: AtomicBool = AtomicBool::new(false);
pub static FIRMWARE_UPGRADE_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

/// Defines a global state variable with thread-safe get/set accessors.
///
/// The type must implement `Clone + Copy + Default`.
macro_rules! global_state {
    ($static_name:ident, $type:ty, set = $setter:ident, get = $getter:ident) => {
        static $static_name: critical_section::Mutex<core::cell::RefCell<Option<$type>>> =
            critical_section::Mutex::new(core::cell::RefCell::new(None));

        pub fn $setter(value: $type) {
            critical_section::with(|cs| {
                $static_name.borrow_ref_mut(cs).replace(value);
            });
        }

        pub fn $getter() -> $type {
            critical_section::with(|cs| {
                $static_name
                    .borrow_ref(cs)
                    .as_ref()
                    .copied()
                    .unwrap_or_default()
            })
        }
    };
}

#[derive(Clone, Copy)]
pub struct AppState {
    pub cloud_event_source: &'static str,
    pub cloud_event_type: &'static str,
    pub boot_timestamp_seconds: u64,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            cloud_event_source: crate::config::CLOUD_EVENTS_SOURCE,
            cloud_event_type: crate::config::CLOUD_EVENT_TYPE,
            boot_timestamp_seconds: 0,
        }
    }
}

global_state!(APP_STATE, AppState, set = set_app_state, get = app_state_snapshot);

#[derive(Clone, Copy)]
pub struct Co2Reading {
    pub ok: bool,
    pub co2_ppm: f32,
    pub temperature: f32,
    pub humidity: f32,
    pub model: &'static str,
    pub name: &'static str,
}

impl Default for Co2Reading {
    fn default() -> Self {
        Self {
            ok: false,
            co2_ppm: 0.0,
            temperature: 0.0,
            humidity: 0.0,
            model: "unknown",
            name: "unknown",
        }
    }
}

global_state!(CO2_READING, Co2Reading, set = set_co2_reading, get = co2_reading);

#[derive(Clone, Copy, Default)]
pub struct DeviceInfo {
    pub ip_address: [u8; 4],
    pub sd_card_size_mb: u32,
}

global_state!(DEVICE_INFO, DeviceInfo, set = set_device_info, get = device_info);
