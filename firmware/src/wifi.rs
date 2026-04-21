use core::ptr::addr_of_mut;
use core::sync::atomic::{AtomicU8, Ordering};
use embassy_time::{Duration, Timer};
use log_04::info;
use zephyr::raw::*;

use crate::led::{self, GREEN, YELLOW};

static WIFI_STATE: AtomicU8 = AtomicU8::new(0);
const STATE_CONNECTED: u8 = 1;
const STATE_DISCONNECTED: u8 = 2;

static mut WIFI_CB: core::mem::MaybeUninit<net_mgmt_event_callback> =
    core::mem::MaybeUninit::uninit();

#[unsafe(no_mangle)]
extern "C" fn wifi_event_handler(
    _cb: *mut net_mgmt_event_callback,
    mgmt_event: u64,
    _iface: *mut net_if,
) {
    unsafe {
        if mgmt_event == ZR_NET_EVENT_WIFI_CONNECT_RESULT {
            WIFI_STATE.store(STATE_CONNECTED, Ordering::Relaxed);
        } else if mgmt_event == ZR_NET_EVENT_WIFI_DISCONNECT_RESULT {
            WIFI_STATE.store(STATE_DISCONNECTED, Ordering::Relaxed);
        }
    }
}

pub fn init() {
    unsafe {
        let cb = addr_of_mut!(WIFI_CB) as *mut net_mgmt_event_callback;
        net_mgmt_init_event_callback(
            cb,
            Some(wifi_event_handler),
            ZR_NET_EVENT_WIFI_CONNECT_RESULT | ZR_NET_EVENT_WIFI_DISCONNECT_RESULT,
        );
        net_mgmt_add_event_callback(cb);
        zr_wifi_connect_stored();
    }
}

#[embassy_executor::task]
pub async fn task() {
    loop {
        match WIFI_STATE.swap(0, Ordering::Relaxed) {
            STATE_CONNECTED => {
                info!("WiFi connected");
                led::set(GREEN);
            }
            STATE_DISCONNECTED => {
                info!("WiFi disconnected, retrying in 5s");
                led::set(YELLOW);
                Timer::after(Duration::from_secs(5)).await;
                unsafe { zr_wifi_connect_stored(); }
            }
            _ => {}
        }
        Timer::after(Duration::from_millis(100)).await;
    }
}
