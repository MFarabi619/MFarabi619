use core::{
    ffi::{c_char, CStr},
    sync::atomic::{AtomicI32, Ordering},
};
use zephyr::time::Duration;

use log::{info, warn};

use crate::utils::errno::{Errno, IntoResult};

const MAX_IDENTITY_LEN: usize = 64;
const _: () = assert!(
    MAX_IDENTITY_LEN >= 23,
    "MAX_IDENTITY_LEN must hold ICCID (22 chars) + NUL"
);

extern "C" {
    fn cellular_initialize() -> i32;
    fn cellular_wait_for_attach(timeout_ms: i32) -> i32;

    fn cellular_initialize_callbacks() -> i32;
    fn cellular_registration_status_string(status: i32) -> *const c_char;

    fn cellular_access_imei(buf: *mut c_char, buf_len: usize) -> i32;
    fn cellular_access_manufacturer(buf: *mut c_char, buf_len: usize) -> i32;
    fn cellular_access_model(buf: *mut c_char, buf_len: usize) -> i32;
    fn cellular_access_firmware(buf: *mut c_char, buf_len: usize) -> i32;
    fn cellular_access_imsi(buf: *mut c_char, buf_len: usize) -> i32;
    fn cellular_access_iccid(buf: *mut c_char, buf_len: usize) -> i32;
}

pub fn initialize() -> Result<(), Errno> {
    unsafe { cellular_initialize() }.ok()
}

pub fn wait_for_attach(timeout: Duration) -> Result<(), Errno> {
    let ms = timeout.to_millis().min(i32::MAX as u64) as i32;
    unsafe { cellular_wait_for_attach(ms) }.ok()
}

pub fn initialize_callbacks() -> Result<(), Errno> {
    unsafe { cellular_initialize_callbacks() }.ok()
}

pub struct CellularIdentity {
    pub imei:         [u8; MAX_IDENTITY_LEN],
    pub manufacturer: [u8; MAX_IDENTITY_LEN],
    pub model:        [u8; MAX_IDENTITY_LEN],
    pub firmware:     [u8; MAX_IDENTITY_LEN],
    pub imsi:         [u8; MAX_IDENTITY_LEN],
    pub iccid:        [u8; MAX_IDENTITY_LEN],
}

impl CellularIdentity {
    fn decode(buf: &[u8]) -> &str {
        let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
        core::str::from_utf8(&buf[..end]).unwrap_or("")
    }

    pub fn iter(&self) -> impl Iterator<Item = (&'static str, &str)> {
        [
            ("imei",         Self::decode(&self.imei)),
            ("manufacturer", Self::decode(&self.manufacturer)),
            ("model",        Self::decode(&self.model)),
            ("firmware",     Self::decode(&self.firmware)),
            ("imsi",         Self::decode(&self.imsi)),
            ("iccid",        Self::decode(&self.iccid)),
        ]
        .into_iter()
    }
}

pub fn access_imei() -> [u8; MAX_IDENTITY_LEN]         { access_field("imei",         cellular_access_imei) }
pub fn access_manufacturer() -> [u8; MAX_IDENTITY_LEN] { access_field("manufacturer", cellular_access_manufacturer) }
pub fn access_model() -> [u8; MAX_IDENTITY_LEN]        { access_field("model",        cellular_access_model) }
pub fn access_firmware() -> [u8; MAX_IDENTITY_LEN]     { access_field("firmware",     cellular_access_firmware) }
pub fn access_imsi() -> [u8; MAX_IDENTITY_LEN]         { access_field("imsi",         cellular_access_imsi) }
pub fn access_iccid() -> [u8; MAX_IDENTITY_LEN]        { access_field("iccid",        cellular_access_iccid) }

pub fn access_identity() -> CellularIdentity {
    CellularIdentity {
        imei:         access_imei(),
        manufacturer: access_manufacturer(),
        model:        access_model(),
        firmware:     access_firmware(),
        imsi:         access_imsi(),
        iccid:        access_iccid(),
    }
}

fn access_field(
    label: &str,
    extern_fn: unsafe extern "C" fn(*mut c_char, usize) -> i32,
) -> [u8; MAX_IDENTITY_LEN] {
    let mut buf = [0u8; MAX_IDENTITY_LEN];
    let rc = unsafe { extern_fn(buf.as_mut_ptr() as *mut c_char, buf.len()) };
    if rc != 0 {
        warn!("cellular: {label} rc={rc}");
    }
    buf
}

static LAST_STATUS: AtomicI32 = AtomicI32::new(-1);

#[no_mangle]
unsafe extern "C" fn on_cellular_registration_status(status: i32) {
    if LAST_STATUS.swap(status, Ordering::SeqCst) == status {
        return;
    }
    let label = unsafe {
        let ptr = cellular_registration_status_string(status);
        if ptr.is_null() {
            "?"
        } else {
            CStr::from_ptr(ptr).to_str().unwrap_or("?")
        }
    };
    info!("registration: {label}");
}

#[no_mangle]
unsafe extern "C" fn on_cellular_modem_info_changed() {
    for (label, value) in access_identity().iter() {
        if !value.is_empty() {
            info!("{label}: {value}");
        }
    }
}

#[no_mangle]
unsafe extern "C" fn on_cellular_l4_connected() {
    info!("cellular online");
}

#[no_mangle]
unsafe extern "C" fn on_cellular_l4_disconnected() {
    info!("cellular disconnected");
}
