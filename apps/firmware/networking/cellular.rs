use core::{cell::UnsafeCell, ffi::c_char, mem::MaybeUninit, sync::atomic::AtomicPtr};
use zephyr::{
    error::to_result_void,
    raw::{
        __device_dts_ord_107, cellular_driver_api, cellular_modem_info_type,
        conn_mgr_mon_resend_status, device, device_is_ready, net_addr_state_NET_ADDR_PREFERRED,
        net_if, net_if_get_first_by_type, net_if_ipv4_get_global_addr, net_if_set_default,
        net_if_up, net_in_addr, net_l2, net_mgmt_add_event_callback, net_mgmt_event_callback,
        net_mgmt_init_event_callback, pm_device_action_PM_DEVICE_ACTION_RESUME,
        pm_device_action_run, sys_reboot, ZR_NET_EVENT_DNS_SERVER_ADD, ZR_NET_EVENT_L4_CONNECTED,
        ZR_NET_EVENT_L4_DISCONNECTED,
    },
    sync::atomic::Ordering,
    sys::sync::Semaphore,
    time::Duration,
};

// Compile-time check: `__device_dts_ord_<N>` symbol name is hand-coded; assert
// it matches what the build generates so a DT reorder fails loudly instead of
// silently grabbing a different device.
const _: () = assert!(zephyr::devicetree::labels::modem::ORD == 107);

use log::{info, warn};

const MAX_IDENTITY_LEN: usize = 64;
const _: () = assert!(
    MAX_IDENTITY_LEN >= 23,
    "MAX_IDENTITY_LEN must hold ICCID (22 chars) + NUL"
);

const ATTACH_TIMEOUT_MS: u64 = 180_000;
const RECOVERY_TIMEOUT_MS: i64 = 120_000;
const WATCHDOG_POLL_MS: u64 = 10_000;
const SYS_REBOOT_COLD: i32 = 1;
const ENODEV: i32 = -19;
const ETIMEDOUT: i32 = -110;
const ENOTCONN: i32 = -128;
const ENOMEM: i32 = -12;

const NET_ROUTE_INFINITE_LIFETIME: u32 = u32::MAX;
const NET_ROUTE_PREFERENCE_MEDIUM: u8 = 0;

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
    static _net_l2_PPP: net_l2;

    // Private subsys/net/ip/route_ipv4.h; symbol exists at link time.
    fn net_route_ipv4_add(
        iface: *mut net_if,
        addr: *mut net_in_addr,
        mask_len: u8,
        nexthop: *mut net_in_addr,
        lifetime: u32,
        preference: u8,
    ) -> *mut core::ffi::c_void;

    // esp-idf API; not in our bindings allowlist but stably present at link time.
    fn gpio_hold_dis(pin: i32) -> i32;
}

// SYS_INIT equivalent — places an `init_entry` in Zephyr's PRE_KERNEL_2/prio-0
// init section. The macro `SYS_INIT(fn, PRE_KERNEL_2, 0)` in C expands to a
// static struct in `.z_init_PRE_KERNEL_2_P_0_SUB_0_`; we reproduce that here.
// Hand-coded GPIO number 13 = walter modem reset (DT: gpio1 13). The ORD
// assert above catches DT reorders that would imply different pin numbering.
unsafe extern "C" fn modem_reset_release() -> core::ffi::c_int {
    unsafe { gpio_hold_dis(13) }
}

#[repr(transparent)]
struct InitEntry(zephyr::raw::init_entry);
unsafe impl Sync for InitEntry {}

#[link_section = ".z_init_PRE_KERNEL_2_P_0_SUB_0_"]
#[used]
static MODEM_RESET_RELEASE: InitEntry = InitEntry(zephyr::raw::init_entry {
    init_fn: Some(modem_reset_release),
    dev: core::ptr::null(),
});

fn modem_device() -> *const device {
    // SAFETY: `__device_dts_ord_<N>` is a static device emitted by Zephyr's
    // build for every DT node. The ORD assert above pins N=107 to the `modem`
    // alias; bindgen exposes the symbol via zephyr-sys.
    unsafe { &__device_dts_ord_107 as *const device }
}

// Replicates the upstream `static inline cellular_get_modem_info` from
// <zephyr/drivers/cellular.h> — bindgen can't bind static inlines, so we
// reach into the device's api vtable directly.
fn cellular_access(field: i32, buf: *mut c_char, buf_len: usize) -> i32 {
    let dev = modem_device();
    unsafe {
        let api = (*dev).api as *const cellular_driver_api;
        match (*api).get_modem_info {
            Some(f) => f(dev, field as cellular_modem_info_type, buf, buf_len),
            None => -88, // -ENOSYS
        }
    }
}

fn install_default_route(iface: *mut net_if) -> zephyr::Result<()> {
    if iface.is_null() {
        return to_result_void(ENODEV);
    }
    let mut default_dst: net_in_addr = unsafe { core::mem::zeroed() };
    let entry = unsafe {
        net_route_ipv4_add(
            iface,
            &mut default_dst,
            0,
            core::ptr::null_mut(),
            NET_ROUTE_INFINITE_LIFETIME,
            NET_ROUTE_PREFERENCE_MEDIUM,
        )
    };
    if entry.is_null() {
        to_result_void(ENOMEM)
    } else {
        Ok(())
    }
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
    if event == unsafe { ZR_NET_EVENT_L4_CONNECTED } {
        info!("online");
        PPP_CONNECTED.give();
    } else if event == unsafe { ZR_NET_EVENT_L4_DISCONNECTED } {
        info!("disconnected");
        PPP_CONNECTED.reset();
    }
}

pub fn initialize() -> zephyr::Result<()> {
    let modem = modem_device();
    if !unsafe { device_is_ready(modem) } {
        warn!("modem device not ready");
        return to_result_void(ENODEV);
    }

    let iface = unsafe { net_if_get_first_by_type(&_net_l2_PPP) };
    if iface.is_null() {
        warn!("no PPP interface found");
        return to_result_void(ENODEV);
    }
    PPP_IFACE.store(iface, Ordering::SeqCst);

    let _ = unsafe { pm_device_action_run(modem, pm_device_action_PM_DEVICE_ACTION_RESUME) };
    to_result_void(unsafe { net_if_up(iface) })?;

    unsafe {
        let cb = (*L4_CB.0.get()).as_mut_ptr();
        net_mgmt_init_event_callback(
            cb,
            Some(on_l4_event),
            ZR_NET_EVENT_L4_CONNECTED | ZR_NET_EVENT_L4_DISCONNECTED | ZR_NET_EVENT_DNS_SERVER_ADD,
        );
        net_mgmt_add_event_callback(cb);
    }

    let _ = registration_watchdog().start();

    wait_for_attach(Duration::millis(ATTACH_TIMEOUT_MS))?;

    for (label, value) in access_identity().iter() {
        if !value.is_empty() {
            info!("{label}: {value}");
        }
    }
    Ok(())
}

fn wait_for_attach(timeout: Duration) -> zephyr::Result<()> {
    let timeout_ms = timeout.to_millis().min(i32::MAX as u64) as i64;

    unsafe { conn_mgr_mon_resend_status() };

    if PPP_CONNECTED.take(timeout).is_err() {
        warn!("Attach did not complete within {timeout_ms} ms — see modem_cellular logs");
        return to_result_void(ETIMEDOUT);
    }

    let iface = PPP_IFACE.load(Ordering::SeqCst);
    let addr = unsafe { net_if_ipv4_get_global_addr(iface, net_addr_state_NET_ADDR_PREFERRED) };
    if addr.is_null() {
        warn!("L4_CONNECTED fired but no IPv4 address on PPP iface");
        return to_result_void(ENOTCONN);
    }
    let b: [u8; 4] = unsafe { core::ptr::read(addr as *const [u8; 4]) };
    info!("ppp ipv4: {}.{}.{}.{}", b[0], b[1], b[2], b[3]);
    unsafe { net_if_set_default(iface) };
    if let Err(e) = install_default_route(iface) {
        warn!("default route: {e}");
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
    let rc = cellular_access(field as i32, buf.as_mut_ptr() as *mut c_char, buf.len());
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


#[cfg(CONFIG_NET_PKT_FILTER_IPV4_HOOK)]
pub mod nat {
    use zephyr::error::to_result_void;
    use zephyr::raw::{
        net_if_get_by_iface, net_if_get_wifi_sap, net_ip_protocol_NET_IPPROTO_ICMP,
        net_ip_protocol_NET_IPPROTO_TCP, net_ip_protocol_NET_IPPROTO_UDP, net_iptable_rule_params,
        net_ipv4_table_rule_add,
    };

    use super::cellular_ppp_iface;

    const ENODEV: i32 = -19;

    struct ProtocolTimeouts {
        proto: u32,
        unreply_s: i32,
        reply_s: i32,
    }

    const PROTOCOLS: [ProtocolTimeouts; 3] = [
        ProtocolTimeouts { proto: net_ip_protocol_NET_IPPROTO_TCP,  unreply_s: 30, reply_s: 300 },
        ProtocolTimeouts { proto: net_ip_protocol_NET_IPPROTO_UDP,  unreply_s: 30, reply_s: 120 },
        ProtocolTimeouts { proto: net_ip_protocol_NET_IPPROTO_ICMP, unreply_s: 15, reply_s: 120 },
    ];

    pub fn initialize() -> zephyr::Result<()> {
        let access_point_iface = unsafe { net_if_get_wifi_sap() };
        let cellular_iface = cellular_ppp_iface();
        if access_point_iface.is_null() || cellular_iface.is_null() {
            return to_result_void(ENODEV);
        }
        let access_point_idx = unsafe { net_if_get_by_iface(access_point_iface) };
        let cellular_idx = unsafe { net_if_get_by_iface(cellular_iface) };

        for protocol in PROTOCOLS {
            let mut params: net_iptable_rule_params = unsafe { core::mem::zeroed() };
            params.input_iface_idx = access_point_idx;
            params.output_iface_idx = cellular_idx;
            params.proto = protocol.proto;
            params.unreply_timeout = protocol.unreply_s;
            params.reply_timeout = protocol.reply_s;
            to_result_void(unsafe { net_ipv4_table_rule_add(&mut params) })?;
        }
        Ok(())
    }
}
