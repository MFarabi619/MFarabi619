use core::{
    ffi::c_char,
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

#[repr(i32)]
#[derive(Clone, Copy)]
enum Field {
    Imei         = 0,
    ModelId      = 1,
    Manufacturer = 2,
    FwVersion    = 3,
    SimImsi      = 4,
    SimIccid     = 5,
}

const REGISTRATION_NAMES: [&str; 6] = [
    "not_registered", "home", "searching", "denied", "unknown", "roaming",
];

fn registration_label(status: i32) -> &'static str {
    usize::try_from(status)
        .ok()
        .and_then(|i| REGISTRATION_NAMES.get(i).copied())
        .unwrap_or("?")
}

extern "C" {
    fn cellular_initialize() -> i32;
    fn cellular_wait_for_attach(timeout_ms: i32) -> i32;
    fn cellular_initialize_callbacks() -> i32;
    fn cellular_access(field: i32, buf: *mut c_char, buf_len: usize) -> i32;
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

fn read_field(label: &str, field: Field) -> [u8; MAX_IDENTITY_LEN] {
    let mut buf = [0u8; MAX_IDENTITY_LEN];
    let rc = unsafe { cellular_access(field as i32, buf.as_mut_ptr() as *mut c_char, buf.len()) };
    if rc != 0 {
        warn!("cellular: {label} rc={rc}");
    }
    buf
}

pub fn access_identity() -> CellularIdentity {
    CellularIdentity {
        imei:         read_field("imei",         Field::Imei),
        manufacturer: read_field("manufacturer", Field::Manufacturer),
        model:        read_field("model",        Field::ModelId),
        firmware:     read_field("firmware",     Field::FwVersion),
        imsi:         read_field("imsi",         Field::SimImsi),
        iccid:        read_field("iccid",        Field::SimIccid),
    }
}

static LAST_STATUS: AtomicI32 = AtomicI32::new(-1);

#[no_mangle]
unsafe extern "C" fn on_cellular_registration_status(status: i32) {
    if LAST_STATUS.swap(status, Ordering::SeqCst) == status {
        return;
    }
    info!("registration: {}", registration_label(status));
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
