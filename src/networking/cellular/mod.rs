use core::{
    cell::UnsafeCell,
    ffi::c_char,
    mem::MaybeUninit,
    sync::atomic::AtomicPtr,
};
use zephyr::{
    raw::{
        conn_mgr_mon_resend_status, device, device_is_ready, net_addr_state_NET_ADDR_PREFERRED,
        net_if, net_if_get_first_by_type, net_if_ipv4_get_global_addr, net_if_set_default,
        net_if_up, net_l2, net_mgmt_add_event_callback, net_mgmt_event_callback,
        net_mgmt_init_event_callback, pm_device_action_PM_DEVICE_ACTION_RESUME,
        pm_device_action_run, sys_reboot,
    },
    sync::atomic::Ordering,
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

const RECOVERY_TIMEOUT_MS: i64 = 120_000;
const WATCHDOG_POLL_MS: u64 = 10_000;
const SYS_REBOOT_COLD: i32 = 1;
const ENODEV: i32 = -19;
const ETIMEDOUT: i32 = -110;
const ENOTCONN: i32 = -128;

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

extern "C" {
    fn cellular_modem_device() -> *const device;
    fn cellular_access(field: i32, buf: *mut c_char, buf_len: usize) -> i32;
    fn cellular_install_default_route() -> i32;
    static _net_l2_PPP: net_l2;
    static CELLULAR_NET_EVENT_L4_CONNECTED: u64;
    static CELLULAR_NET_EVENT_L4_DISCONNECTED: u64;
    static CELLULAR_NET_EVENT_DNS_SERVER_ADD: u64;
}

static PPP_CONNECTED: Semaphore = Semaphore::new(0, 1);
static PPP_IFACE: AtomicPtr<net_if> = AtomicPtr::new(core::ptr::null_mut());

/// `improper_ctypes_definitions` is advisory for the pointer return —
/// `net_if` transitively contains `k_spinlock`.
#[no_mangle]
#[allow(improper_ctypes_definitions)]
pub extern "C" fn cellular_ppp_iface() -> *mut net_if {
    PPP_IFACE.load(Ordering::SeqCst)
}

struct L4CbCell(UnsafeCell<MaybeUninit<net_mgmt_event_callback>>);
unsafe impl Sync for L4CbCell {}
static L4_CB: L4CbCell = L4CbCell(UnsafeCell::new(MaybeUninit::uninit()));

unsafe extern "C" fn on_l4_event(
    _cb: *mut net_mgmt_event_callback,
    event: u64,
    iface: *mut net_if,
) {
    if iface != PPP_IFACE.load(Ordering::SeqCst) {
        return;
    }
    if event == unsafe { CELLULAR_NET_EVENT_L4_CONNECTED } {
        info!("cellular online");
        PPP_CONNECTED.give();
    } else if event == unsafe { CELLULAR_NET_EVENT_L4_DISCONNECTED } {
        info!("cellular disconnected");
        PPP_CONNECTED.reset();
    }
}

pub fn initialize() -> Result<(), Errno> {
    let modem = unsafe { cellular_modem_device() };
    if !unsafe { device_is_ready(modem) } {
        warn!("modem device not ready");
        return ENODEV.ok();
    }

    let iface = unsafe { net_if_get_first_by_type(&_net_l2_PPP) };
    if iface.is_null() {
        warn!("no PPP interface found");
        return ENODEV.ok();
    }
    PPP_IFACE.store(iface, Ordering::SeqCst);

    let _ = unsafe { pm_device_action_run(modem, pm_device_action_PM_DEVICE_ACTION_RESUME) };
    unsafe { net_if_up(iface) }.ok()?;

    unsafe {
        let cb = (*L4_CB.0.get()).as_mut_ptr();
        net_mgmt_init_event_callback(
            cb,
            Some(on_l4_event),
            CELLULAR_NET_EVENT_L4_CONNECTED
                | CELLULAR_NET_EVENT_L4_DISCONNECTED
                | CELLULAR_NET_EVENT_DNS_SERVER_ADD,
        );
        net_mgmt_add_event_callback(cb);
    }

    let _ = registration_watchdog().start();
    Ok(())
}

pub fn wait_for_attach(timeout: Duration) -> Result<(), Errno> {
    let timeout_ms = timeout.to_millis().min(i32::MAX as u64) as i64;

    unsafe { conn_mgr_mon_resend_status() };

    if PPP_CONNECTED.take(timeout).is_err() {
        warn!("Attach did not complete within {timeout_ms} ms — see modem_cellular logs");
        return ETIMEDOUT.ok();
    }

    let iface = PPP_IFACE.load(Ordering::SeqCst);
    let addr = unsafe { net_if_ipv4_get_global_addr(iface, net_addr_state_NET_ADDR_PREFERRED) };
    if addr.is_null() {
        warn!("L4_CONNECTED fired but no IPv4 address on PPP iface");
        return ENOTCONN.ok();
    }
    let b: [u8; 4] = unsafe { core::ptr::read(addr as *const [u8; 4]) };
    info!("cellular ppp ipv4: {}.{}.{}.{}", b[0], b[1], b[2], b[3]);
    unsafe { net_if_set_default(iface) };
    if let Err(e) = unsafe { cellular_install_default_route() }.ok() {
        warn!("cellular default route: {e}");
    }
    Ok(())
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

#[zephyr::thread(stack_size = 1024)]
fn registration_watchdog() {
    let mut last_online_ms = unsafe { zephyr::raw::k_uptime_get() };
    loop {
        zephyr::time::sleep(Duration::millis(WATCHDOG_POLL_MS));
        let now = unsafe { zephyr::raw::k_uptime_get() };
        let iface = PPP_IFACE.load(Ordering::SeqCst);
        let has_ipv4 = !iface.is_null()
            && !unsafe { net_if_ipv4_get_global_addr(iface, net_addr_state_NET_ADDR_PREFERRED) }
                .is_null();
        if has_ipv4 {
            last_online_ms = now;
        } else if now - last_online_ms > RECOVERY_TIMEOUT_MS {
            warn!("cellular offline for >{RECOVERY_TIMEOUT_MS} ms — rebooting");
            unsafe { sys_reboot(SYS_REBOOT_COLD) };
        }
    }
}
