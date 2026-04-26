use core::cell::UnsafeCell;

use core::sync::atomic::{AtomicU8, Ordering};
use embassy_time::{Duration, Timer};
use log_04::info;
use zephyr::raw::*;

use crate::led::{self, GREEN, MAGENTA, YELLOW};

static WIFI_STATE: AtomicU8 = AtomicU8::new(0);
const EVENT_CONNECTED: u8 = 1;
const EVENT_DISCONNECTED: u8 = 2;
const EVENT_SCAN_DONE: u8 = 3;
const EVENT_AP_ENABLED: u8 = 4;

const STA_CONNECT_TIMEOUT_SECONDS: u64 = 15;
const STA_RETRY_DELAY_SECONDS: u64 = 5;

const AP_SSID: &[u8] = b"ceratina-access-point";
const AP_PSK: &[u8] = b"ceratina";
const AP_CHANNEL: u8 = 6;

const MODE_CONNECTING: u8 = 0;
const MODE_CONNECTED: u8 = 1;
const MODE_PROVISIONING: u8 = 2;

static CURRENT_MODE: AtomicU8 = AtomicU8::new(MODE_CONNECTING);

pub struct ScanResult {
    pub ssid: [u8; 33],
    pub ssid_length: u8,
    pub rssi: i8,
    pub channel: u8,
}

const MAX_SCAN_RESULTS: usize = 16;

struct ScanBuffer {
    results: UnsafeCell<[core::mem::MaybeUninit<ScanResult>; MAX_SCAN_RESULTS]>,
}

unsafe impl Sync for ScanBuffer {}

static SCAN_BUFFER: ScanBuffer = ScanBuffer {
    results: UnsafeCell::new(unsafe { core::mem::MaybeUninit::uninit().assume_init() }),
};
static SCAN_COUNT: AtomicU8 = AtomicU8::new(0);
static SCAN_IN_PROGRESS: AtomicU8 = AtomicU8::new(0);

struct CallbackStorage {
    inner: UnsafeCell<core::mem::MaybeUninit<net_mgmt_event_callback>>,
}

unsafe impl Sync for CallbackStorage {}

static WIFI_CB: CallbackStorage = CallbackStorage {
    inner: UnsafeCell::new(core::mem::MaybeUninit::uninit()),
};

#[unsafe(no_mangle)]
extern "C" fn wifi_event_handler(
    cb: *mut net_mgmt_event_callback,
    mgmt_event: u64,
    _iface: *mut net_if,
) {
    unsafe {
        if mgmt_event == ZR_NET_EVENT_WIFI_CONNECT_RESULT {
            WIFI_STATE.store(EVENT_CONNECTED, Ordering::Relaxed);
        } else if mgmt_event == ZR_NET_EVENT_WIFI_DISCONNECT_RESULT {
            WIFI_STATE.store(EVENT_DISCONNECTED, Ordering::Relaxed);
        } else if mgmt_event == ZR_NET_EVENT_WIFI_SCAN_RESULT {
            let count = SCAN_COUNT.load(Ordering::Relaxed) as usize;
            if count < MAX_SCAN_RESULTS && !(*cb).info.is_null() {
                let scan_result = &*((*cb).info as *const wifi_scan_result);
                let mut entry = ScanResult {
                    ssid: [0; 33],
                    ssid_length: scan_result.ssid_length,
                    rssi: scan_result.rssi,
                    channel: scan_result.channel,
                };
                let length = (scan_result.ssid_length as usize).min(32);
                entry.ssid[..length].copy_from_slice(&scan_result.ssid[..length]);
                let results = SCAN_BUFFER.results.get();
                (*results)[count].write(entry);
                SCAN_COUNT.store((count + 1) as u8, Ordering::Relaxed);
            }
        } else if mgmt_event == ZR_NET_EVENT_WIFI_SCAN_DONE {
            SCAN_IN_PROGRESS.store(0, Ordering::Relaxed);
            WIFI_STATE.store(EVENT_SCAN_DONE, Ordering::Relaxed);
        } else if mgmt_event == ZR_NET_EVENT_WIFI_AP_ENABLE_RESULT {
            WIFI_STATE.store(EVENT_AP_ENABLED, Ordering::Relaxed);
        }
    }
}

pub fn init() {
    unsafe {
        let cb = WIFI_CB.inner.get() as *mut net_mgmt_event_callback;
        net_mgmt_init_event_callback(
            cb,
            Some(wifi_event_handler),
            ZR_NET_EVENT_WIFI_CONNECT_RESULT
                | ZR_NET_EVENT_WIFI_DISCONNECT_RESULT
                | ZR_NET_EVENT_WIFI_SCAN_RESULT
                | ZR_NET_EVENT_WIFI_SCAN_DONE
                | ZR_NET_EVENT_WIFI_AP_ENABLE_RESULT
                | ZR_NET_EVENT_WIFI_AP_STA_CONNECTED,
        );
        net_mgmt_add_event_callback(cb);

        if zr_wifi_credentials_is_empty() {
            info!("No stored WiFi credentials, starting AP provisioning");
            start_ap();
        } else {
            info!("Stored WiFi credentials found, connecting");
            CURRENT_MODE.store(MODE_CONNECTING, Ordering::Relaxed);
            zr_wifi_connect_stored();
        }
    }
}

fn start_ap() {
    CURRENT_MODE.store(MODE_PROVISIONING, Ordering::Relaxed);
    led::set(MAGENTA);
    unsafe {
        let result = zr_wifi_ap_setup_network();
        if result != 0 {
            info!("Failed to setup AP network: {}", result);
        }

        let result = zr_wifi_ap_enable(
            AP_SSID.as_ptr(),
            AP_SSID.len() as u8,
            AP_PSK.as_ptr(),
            AP_PSK.len() as u8,
            AP_CHANNEL,
        );
        if result != 0 {
            info!("Failed to enable AP: {}", result);
        }
    }
}

pub fn is_provisioning() -> bool {
    CURRENT_MODE.load(Ordering::Relaxed) == MODE_PROVISIONING
}

pub fn start_scan() {
    if SCAN_IN_PROGRESS.load(Ordering::Relaxed) != 0 {
        return;
    }
    SCAN_COUNT.store(0, Ordering::Relaxed);
    SCAN_IN_PROGRESS.store(1, Ordering::Relaxed);
    unsafe {
        zr_wifi_scan();
    }
}

pub fn is_scan_in_progress() -> bool {
    SCAN_IN_PROGRESS.load(Ordering::Relaxed) != 0
}

pub fn scan_result_count() -> u8 {
    SCAN_COUNT.load(Ordering::Relaxed)
}

pub unsafe fn get_scan_result(index: usize) -> *const ScanResult {
    unsafe {
        let results = SCAN_BUFFER.results.get();
        (*results)[index].assume_init_ref() as *const ScanResult
    }
}

pub fn connect_to_network(ssid: &[u8], password: &[u8]) -> i32 {
    unsafe {
        let result = zr_wifi_credentials_delete_all();
        if result != 0 {
            info!("Failed to clear old credentials: {}", result);
        }

        let result = zr_wifi_credentials_set(
            ssid.as_ptr(),
            ssid.len(),
            password.as_ptr(),
            password.len(),
        );
        if result != 0 {
            info!("Failed to store credentials: {}", result);
            return result;
        }

        CURRENT_MODE.store(MODE_CONNECTING, Ordering::Relaxed);
        led::set(YELLOW);

        zr_wifi_ap_disable();
        zr_wifi_connect_stored()
    }
}

pub fn delete_credentials() -> i32 {
    unsafe { zr_wifi_credentials_delete_all() }
}

#[embassy_executor::task]
pub async fn task() {
    let mut connect_start = embassy_time::Instant::now();

    loop {
        let event = WIFI_STATE.swap(0, Ordering::Relaxed);
        let mode = CURRENT_MODE.load(Ordering::Relaxed);

        match mode {
            MODE_CONNECTING => match event {
                EVENT_CONNECTED => {
                    info!("WiFi connected");
                    CURRENT_MODE.store(MODE_CONNECTED, Ordering::Relaxed);
                    led::set(GREEN);
                }
                _ => {
                    if connect_start.elapsed() > Duration::from_secs(STA_CONNECT_TIMEOUT_SECONDS) {
                        info!("STA connect timeout, switching to AP provisioning");
                        unsafe { zr_wifi_disconnect(); }
                        start_ap();
                    }
                }
            },
            MODE_CONNECTED => match event {
                EVENT_DISCONNECTED => {
                    info!("WiFi disconnected, retrying in {}s", STA_RETRY_DELAY_SECONDS);
                    led::set(YELLOW);
                    Timer::after(Duration::from_secs(STA_RETRY_DELAY_SECONDS)).await;
                    CURRENT_MODE.store(MODE_CONNECTING, Ordering::Relaxed);
                    connect_start = embassy_time::Instant::now();
                    unsafe { zr_wifi_connect_stored(); }
                }
                _ => {}
            },
            MODE_PROVISIONING => match event {
                EVENT_CONNECTED => {
                    info!("WiFi connected via provisioning");
                    CURRENT_MODE.store(MODE_CONNECTED, Ordering::Relaxed);
                    led::set(GREEN);
                }
                EVENT_AP_ENABLED => {
                    info!("AP enabled: SSID={}", unsafe { core::str::from_utf8_unchecked(AP_SSID) });
                }
                _ => {}
            },
            _ => {}
        }

        Timer::after(Duration::from_millis(100)).await;
    }
}
