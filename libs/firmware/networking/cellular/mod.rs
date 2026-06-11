use core::ffi::{c_char, c_void};
use zephyr::{
    raw::{
        conn_mgr_mon_resend_status, net_addr_state_NET_ADDR_PREFERRED, net_if,
        net_if_ipv4_get_global_addr, net_if_set_default, sys_reboot,
    },
    sync::atomic::{AtomicI32, AtomicI64, Ordering},
    sys::sync::Semaphore,
    time::Duration,
};

use log::{info, warn};

use crate::utils::errno::{Errno, IntoResult};

const MAX_IDENTITY_LEN: usize = 64;
const _: () = assert!(
    MAX_IDENTITY_LEN >= 23,
    "MAX_IDENTITY_LEN must hold ICCID (22 chars) + NUL"
);

const REGISTRATION_RECOVERY_TIMEOUT_MS: i64 = 120_000;
const REGISTRATION_WATCHDOG_POLL_MS: u64 = 10_000;
const SYS_REBOOT_COLD: i32 = 1;

#[repr(i32)]
#[derive(Clone, Copy)]
enum Field {
    Imei = 0,
    ModelId = 1,
    Manufacturer = 2,
    FwVersion = 3,
    SimImsi = 4,
    SimIccid = 5,
}

const REGISTRATION_NAMES: [&str; 6] = [
    "not_registered",
    "home",
    "searching",
    "denied",
    "unknown",
    "roaming",
];

fn registration_label(status: i32) -> &'static str {
    usize::try_from(status)
        .ok()
        .and_then(|i| REGISTRATION_NAMES.get(i).copied())
        .unwrap_or("?")
}

fn registration_is_attached(status: i32) -> bool {
    status == 1 || status == 5
}

extern "C" {
    fn cellular_initialize() -> i32;
    fn cellular_initialize_callbacks() -> i32;
    fn cellular_access(field: i32, buf: *mut c_char, buf_len: usize) -> i32;
    fn cellular_ppp_iface() -> *mut c_void;
}

const ETIMEDOUT: i32 = -110;
const ENOTCONN: i32 = -128;

static PPP_CONNECTED: Semaphore = Semaphore::new(0, 1);
static DNS_SERVER_ADDED: Semaphore = Semaphore::new(0, 1);

pub fn initialize() -> Result<(), Errno> {
    unsafe { cellular_initialize() }.ok()?;
    LAST_ATTACHED_MS.store(unsafe { zephyr::raw::k_uptime_get() }, Ordering::SeqCst);
    let _ = registration_watchdog().start();
    Ok(())
}

pub fn wait_for_attach(timeout: Duration) -> Result<(), Errno> {
    let timeout_ms = timeout.to_millis().min(i32::MAX as u64) as i64;
    let start = unsafe { zephyr::raw::k_uptime_get() };

    unsafe { conn_mgr_mon_resend_status() };

    if PPP_CONNECTED.take(timeout).is_err() {
        warn!("Attach did not complete within {timeout_ms} ms — see modem_cellular logs");
        return ETIMEDOUT.ok();
    }

    let iface = unsafe { cellular_ppp_iface() as *mut net_if };
    let addr = unsafe { net_if_ipv4_get_global_addr(iface, net_addr_state_NET_ADDR_PREFERRED) };
    if addr.is_null() {
        warn!("L4_CONNECTED fired but no IPv4 address on PPP iface");
        return ENOTCONN.ok();
    }
    let b: [u8; 4] = unsafe { core::ptr::read(addr as *const [u8; 4]) };
    info!("cellular ppp ipv4: {}.{}.{}.{}", b[0], b[1], b[2], b[3]);
    unsafe { net_if_set_default(iface) };

    let mut dns_deadline = timeout_ms - (unsafe { zephyr::raw::k_uptime_get() } - start);
    if dns_deadline < 1000 {
        dns_deadline = 10_000;
    }
    if DNS_SERVER_ADDED
        .take(Duration::millis(dns_deadline as u64))
        .is_err()
    {
        warn!("DNS server not registered within {dns_deadline} ms — proceeding anyway");
    } else {
        info!("DNS server registered");
    }
    Ok(())
}

pub fn initialize_callbacks() -> Result<(), Errno> {
    unsafe { cellular_initialize_callbacks() }.ok()
}

pub struct CellularIdentity {
    pub imei: [u8; MAX_IDENTITY_LEN],
    pub manufacturer: [u8; MAX_IDENTITY_LEN],
    pub model: [u8; MAX_IDENTITY_LEN],
    pub firmware: [u8; MAX_IDENTITY_LEN],
    pub imsi: [u8; MAX_IDENTITY_LEN],
    pub iccid: [u8; MAX_IDENTITY_LEN],
}

impl CellularIdentity {
    fn decode(buf: &[u8]) -> &str {
        let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
        core::str::from_utf8(&buf[..end]).unwrap_or("")
    }

    pub fn iter(&self) -> impl Iterator<Item = (&'static str, &str)> {
        [
            ("imei", Self::decode(&self.imei)),
            ("manufacturer", Self::decode(&self.manufacturer)),
            ("model", Self::decode(&self.model)),
            ("firmware", Self::decode(&self.firmware)),
            ("imsi", Self::decode(&self.imsi)),
            ("iccid", Self::decode(&self.iccid)),
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
        imei: read_field("imei", Field::Imei),
        manufacturer: read_field("manufacturer", Field::Manufacturer),
        model: read_field("model", Field::ModelId),
        firmware: read_field("firmware", Field::FwVersion),
        imsi: read_field("imsi", Field::SimImsi),
        iccid: read_field("iccid", Field::SimIccid),
    }
}

static LAST_STATUS: AtomicI32 = AtomicI32::new(-1);
static LAST_ATTACHED_MS: AtomicI64 = AtomicI64::new(0);

#[no_mangle]
unsafe extern "C" fn on_cellular_registration_status(status: i32) {
    if registration_is_attached(status) {
        LAST_ATTACHED_MS.store(unsafe { zephyr::raw::k_uptime_get() }, Ordering::SeqCst);
    }
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
    PPP_CONNECTED.give();
}

#[no_mangle]
unsafe extern "C" fn on_cellular_l4_disconnected() {
    info!("cellular disconnected");
    PPP_CONNECTED.reset();
}

#[no_mangle]
unsafe extern "C" fn on_cellular_dns_server_added() {
    DNS_SERVER_ADDED.give();
}

#[zephyr::thread(stack_size = 1024)]
fn registration_watchdog() {
    loop {
        zephyr::time::sleep(Duration::millis(REGISTRATION_WATCHDOG_POLL_MS));
        let now = unsafe { zephyr::raw::k_uptime_get() };
        let last = LAST_ATTACHED_MS.load(Ordering::SeqCst);
        if now - last > REGISTRATION_RECOVERY_TIMEOUT_MS {
            warn!("cellular unattached for >{REGISTRATION_RECOVERY_TIMEOUT_MS} ms — rebooting");
            unsafe { sys_reboot(SYS_REBOOT_COLD) };
        }
    }
}
