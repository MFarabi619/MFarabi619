use core::ffi::{c_char, CStr};
use core::sync::atomic::{AtomicI32, Ordering};
use core::time::Duration;

use log::{info, warn};

use firmware::utils::errno::{Errno, IntoResult};

const MAX_IDENTITY_LEN: usize = 64;
const _: () = assert!(
    MAX_IDENTITY_LEN >= 23,
    "MAX_IDENTITY_LEN must hold ICCID (22 chars) + NUL"
);

extern "C" {
    fn cellularInitialize() -> i32;
    fn cellularWaitForAttach(timeout_ms: i32) -> i32;

    fn cellularInitializeCallbacks() -> i32;
    fn cellularRegistrationStatusString(status: i32) -> *const c_char;

    fn cellularAccessIMEI(buf: *mut c_char, buf_len: usize) -> i32;
    fn cellularAccessManufacturer(buf: *mut c_char, buf_len: usize) -> i32;
    fn cellularAccessModel(buf: *mut c_char, buf_len: usize) -> i32;
    fn cellularAccessFirmware(buf: *mut c_char, buf_len: usize) -> i32;
    fn cellularAccessIMSI(buf: *mut c_char, buf_len: usize) -> i32;
    fn cellularAccessICCID(buf: *mut c_char, buf_len: usize) -> i32;
}

pub fn initialize() -> Result<(), Errno> {
    unsafe { cellularInitialize() }.ok()
}

pub fn waitForAttach(timeout: Duration) -> Result<(), Errno> {
    let ms = timeout.as_millis().min(i32::MAX as u128) as i32;
    unsafe { cellularWaitForAttach(ms) }.ok()
}

pub fn initializeCallbacks() -> Result<(), Errno> {
    unsafe { cellularInitializeCallbacks() }.ok()
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

pub fn accessIMEI() -> [u8; MAX_IDENTITY_LEN]         { accessField("imei",         cellularAccessIMEI) }
pub fn accessManufacturer() -> [u8; MAX_IDENTITY_LEN] { accessField("manufacturer", cellularAccessManufacturer) }
pub fn accessModel() -> [u8; MAX_IDENTITY_LEN]        { accessField("model",        cellularAccessModel) }
pub fn accessFirmware() -> [u8; MAX_IDENTITY_LEN]     { accessField("firmware",     cellularAccessFirmware) }
pub fn accessIMSI() -> [u8; MAX_IDENTITY_LEN]         { accessField("imsi",         cellularAccessIMSI) }
pub fn accessICCID() -> [u8; MAX_IDENTITY_LEN]        { accessField("iccid",        cellularAccessICCID) }

pub fn accessIdentity() -> CellularIdentity {
    CellularIdentity {
        imei:         accessIMEI(),
        manufacturer: accessManufacturer(),
        model:        accessModel(),
        firmware:     accessFirmware(),
        imsi:         accessIMSI(),
        iccid:        accessICCID(),
    }
}

fn accessField(
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
unsafe extern "C" fn onCellularRegistrationStatus(status: i32) {
    if LAST_STATUS.swap(status, Ordering::SeqCst) == status {
        return;
    }
    let label = unsafe {
        let ptr = cellularRegistrationStatusString(status);
        if ptr.is_null() {
            "?"
        } else {
            CStr::from_ptr(ptr).to_str().unwrap_or("?")
        }
    };
    info!("registration: {label}");
}

#[no_mangle]
unsafe extern "C" fn onCellularModemInfoChanged() {
    for (label, value) in accessIdentity().iter() {
        if !value.is_empty() {
            info!("{label}: {value}");
        }
    }
}

#[no_mangle]
unsafe extern "C" fn onCellularL4Connected() {
    info!("cellular online");
}

#[no_mangle]
unsafe extern "C" fn onCellularL4Disconnected() {
    info!("cellular disconnected");
}
