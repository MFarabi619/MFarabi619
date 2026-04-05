use core::sync::atomic::AtomicBool;

pub static WIFI_INITIALIZED: AtomicBool = AtomicBool::new(false);
pub static FIRMWARE_UPGRADE_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

#[derive(Clone, Copy)]
pub struct AppState {
    pub cloud_event_source: &'static str,
    pub cloud_event_type: &'static str,
    pub boot_timestamp_seconds: u64,
}

static APP_STATE: critical_section::Mutex<core::cell::RefCell<Option<AppState>>> =
    critical_section::Mutex::new(core::cell::RefCell::new(None));

pub const DEFAULT_CLOUD_EVENT_SOURCE: &str =
    "urn:apidae-systems:tenant:p-uot-ins:site:university-of-ottawa";
pub const DEFAULT_CLOUD_EVENT_TYPE: &str = "com.apidae.system.device.status.v1";

pub fn set_app_state(app_state: AppState) {
    critical_section::with(|critical_section| {
        APP_STATE
            .borrow_ref_mut(critical_section)
            .replace(app_state);
    });
}

pub fn app_state_snapshot() -> AppState {
    critical_section::with(|critical_section| {
        APP_STATE
            .borrow_ref(critical_section)
            .as_ref()
            .copied()
            .unwrap_or(AppState {
                cloud_event_source: DEFAULT_CLOUD_EVENT_SOURCE,
                cloud_event_type: DEFAULT_CLOUD_EVENT_TYPE,
                boot_timestamp_seconds: 0,
            })
    })
}
