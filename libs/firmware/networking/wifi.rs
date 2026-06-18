use core::{
    cell::UnsafeCell,
    ffi::{c_char, c_void},
    mem::MaybeUninit,
};
use zephyr::{
    raw::{
        net_addr_state_NET_ADDR_PREFERRED, net_addr_type_NET_ADDR_MANUAL, net_dhcpv4_server_start,
        net_dhcpv4_server_stop, net_if, net_if_get_first_wifi, net_if_get_wifi_sap,
        net_if_ipv4_addr_add, net_if_ipv4_addr_rm, net_if_ipv4_get_global_addr, net_if_ipv4_get_gw,
        net_if_ipv4_set_gw, net_if_ipv4_set_netmask_by_addr, net_in_addr,
        net_ipv4_is_addr_unspecified, net_mgmt_NET_REQUEST_WIFI_AP_DISABLE,
        net_mgmt_NET_REQUEST_WIFI_AP_ENABLE, net_mgmt_NET_REQUEST_WIFI_CONNECT_STORED,
        net_mgmt_add_event_callback, net_mgmt_del_event_callback, net_mgmt_event_callback,
        net_mgmt_init_event_callback, wifi_connect_req_params,
        wifi_credentials_for_each_ssid, wifi_credentials_get_by_ssid_personal_struct,
        wifi_credentials_is_empty, wifi_credentials_personal,
        wifi_frequency_bands_WIFI_FREQ_BAND_2_4_GHZ, wifi_mfp_options_WIFI_MFP_OPTIONAL,
        wifi_security_type_WIFI_SECURITY_TYPE_NONE, ZR_NET_EVENT_IPV4_DHCP_BOUND,
    },
    time::Duration,
};

use log::{info, warn};

use zephyr::error::to_result_void;

const WIFI_CHANNEL_ANY: u8 = 255;
const ENODEV: i32 = -19;
const EAGAIN: i32 = -11;
const ENOMEM: i32 = -12;
const ETIMEDOUT: i32 = -110;

// Parsed from the dhcpv4-server DNS-option kconfig at compile time, so the AP
// iface IP and the DHCP-advertised DNS stay in sync from a single source.
// Pool starts at .11, netmask is conventional /24.
const AP_IPV4: [u8; 4] = parse_ipv4(zephyr::kconfig::CONFIG_NET_DHCPV4_SERVER_OPTION_DNS_ADDRESS);
const AP_NETMASK: [u8; 4] = [255, 255, 255, 0];
const AP_POOL_START: [u8; 4] = [AP_IPV4[0], AP_IPV4[1], AP_IPV4[2], 11];

const fn parse_ipv4(s: &str) -> [u8; 4] {
    let b = s.as_bytes();
    let mut out = [0u8; 4];
    let (mut octet, mut acc, mut i) = (0usize, 0u8, 0usize);
    while i < b.len() {
        let c = b[i];
        if c == b'.' {
            out[octet] = acc;
            octet += 1;
            acc = 0;
        } else {
            acc = acc * 10 + (c - b'0');
        }
        i += 1;
    }
    out[octet] = acc;
    out
}

// `net_route_ipv4_add` lives only in private subsys/net/ip/route_ipv4.h —
// not bindgen-visible. The symbol is a real function (route_ipv4.c, non-inline),
// so we hand-declare the extern and call it directly. The returned
// `net_route_entry *` is opaque; we only check it for NULL.
const NET_ROUTE_INFINITE_LIFETIME: u32 = u32::MAX;
const NET_ROUTE_PREFERENCE_MEDIUM: u8 = 0;

extern "C" {
    fn net_route_ipv4_add(
        iface: *mut net_if,
        addr: *mut net_in_addr,
        mask_len: u8,
        nexthop: *mut net_in_addr,
        lifetime: u32,
        preference: u8,
    ) -> *mut core::ffi::c_void;
}

fn in_addr_v4(bytes: [u8; 4]) -> net_in_addr {
    let mut addr: net_in_addr = unsafe { core::mem::zeroed() };
    unsafe { *(&mut addr as *mut _ as *mut [u8; 4]) = bytes };
    addr
}

pub mod ap {
    use super::*;

    struct CbCell(UnsafeCell<MaybeUninit<net_mgmt_event_callback>>);
    unsafe impl Sync for CbCell {}
    static FALLBACK_CB: CbCell = CbCell(UnsafeCell::new(MaybeUninit::uninit()));

    unsafe extern "C" fn on_dhcp_bound(
        cb: *mut net_mgmt_event_callback,
        _event: u64,
        iface: *mut net_if,
    ) {
        if iface == unsafe { net_if_get_wifi_sap() } {
            return;
        }
        info!("ap: STA got IP — tearing down fallback AP");
        let _ = disable();
        unsafe { net_mgmt_del_event_callback(cb) };
    }

    /// Fallback AP at 192.168.4.1/wlan1 conflicts with the peer-AP subnet on STA,
    /// stalling DHCP in `selecting`. Disable the AP the moment STA gets a lease.
    pub(super) fn start_fallback_watchdog() {
        unsafe {
            let cb = (*FALLBACK_CB.0.get()).as_mut_ptr();
            net_mgmt_init_event_callback(cb, Some(on_dhcp_bound), ZR_NET_EVENT_IPV4_DHCP_BOUND);
            net_mgmt_add_event_callback(cb);
        }
    }

    /// Pulls the first stored SSID via `wifi_credentials_for_each_ssid` into the buffer.
    /// Returns Some(len) on capture, None if the store is empty.
    fn first_stored_ssid(buf: &mut [u8; 32]) -> Option<usize> {
        if unsafe { wifi_credentials_is_empty() } {
            return None;
        }

        struct Sink<'a> {
            dst: &'a mut [u8; 32],
            len: usize,
            captured: bool,
        }

        unsafe extern "C" fn cb(arg: *mut c_void, ssid: *const c_char, ssid_len: usize) {
            let sink = unsafe { &mut *(arg as *mut Sink<'_>) };
            if sink.captured {
                return;
            }
            let n = ssid_len.min(sink.dst.len());
            unsafe {
                core::ptr::copy_nonoverlapping(ssid as *const u8, sink.dst.as_mut_ptr(), n);
            }
            sink.len = n;
            sink.captured = true;
        }

        let mut sink = Sink { dst: buf, len: 0, captured: false };
        unsafe {
            wifi_credentials_for_each_ssid(Some(cb), &mut sink as *mut _ as *mut c_void);
        }
        sink.captured.then_some(sink.len)
    }

    /// SSID + PSK from `wifi_credentials` if any are stored; otherwise the
    /// hostname comes up as an open AP for first-time provisioning.
    pub fn initialize() -> zephyr::Result<()> {
        let mut ssid_buf: [u8; 32] = [0; 32];
        let stored_len = first_stored_ssid(&mut ssid_buf);

        let (ssid_ptr, ssid_len, creds_opt) = if let Some(n) = stored_len {
            let mut creds: wifi_credentials_personal = unsafe { core::mem::zeroed() };
            let rc = unsafe {
                wifi_credentials_get_by_ssid_personal_struct(
                    ssid_buf.as_ptr() as *const c_char,
                    n,
                    &mut creds,
                )
            };
            let creds = if rc == 0 && creds.password_len > 0 {
                Some(creds)
            } else {
                if rc != 0 {
                    warn!("cred load: errno {rc}");
                }
                None
            };
            (ssid_buf.as_ptr() as *const c_char, n, creds)
        } else {
            let hostname = zephyr::kconfig::CONFIG_NET_HOSTNAME;
            (hostname.as_ptr() as *const c_char, hostname.len(), None)
        };

        let ssid_str = unsafe {
            core::str::from_utf8_unchecked(core::slice::from_raw_parts(ssid_ptr as *const u8, ssid_len))
        };

        // Must run BEFORE AP_ENABLE: clients that associate before the gw/netmask
        // call lands get a broken DHCP lease (no gateway).
        match dhcpv4_server_start() {
            Ok(()) => info!("dhcpv4 server up on 192.168.4.1/24"),
            Err(e) => warn!("dhcpv4 server start {e}"),
        }

        if let Err(e) = install_subnet_route() {
            warn!("subnet route: {e}");
        }

        let iface = unsafe { net_if_get_wifi_sap() };
        if iface.is_null() {
            return to_result_void(ENODEV);
        }

        let mut params: wifi_connect_req_params = unsafe { core::mem::zeroed() };
        params.ssid = ssid_ptr as *const u8;
        params.ssid_length = ssid_len as u8;
        if let Some(c) = creds_opt.as_ref() {
            info!("using stored cred for '{ssid_str}'");
            params.psk = c.password.as_ptr() as *const u8;
            params.psk_length = c.password_len as u8;
            params.security = c.header.type_ as u32;
            params.mfp = wifi_mfp_options_WIFI_MFP_OPTIONAL;
        } else {
            info!("no stored cred — open AP '{ssid_str}' for provisioning");
            params.security = wifi_security_type_WIFI_SECURITY_TYPE_NONE;
        }
        params.channel = WIFI_CHANNEL_ANY;
        params.band = wifi_frequency_bands_WIFI_FREQ_BAND_2_4_GHZ as u8;

        to_result_void(unsafe {
            net_mgmt_NET_REQUEST_WIFI_AP_ENABLE(
                0,
                iface,
                &mut params as *mut _ as *mut c_void,
                core::mem::size_of::<wifi_connect_req_params>(),
            )
        })?;
        info!("enabled ssid={ssid_str}");

        Ok(())
    }

    pub(super) fn disable() -> zephyr::Result<()> {
        let iface = unsafe { net_if_get_wifi_sap() };
        if iface.is_null() {
            return to_result_void(ENODEV);
        }
        let rc = unsafe { net_dhcpv4_server_stop(iface) };
        if rc != 0 && rc != -2
        /* -ENOENT */
        {
            warn!("ap: dhcpv4 server stop: {rc}");
        }
        let ap_addr = super::in_addr_v4(AP_IPV4);
        if !unsafe { net_if_ipv4_addr_rm(iface, &ap_addr) } {
            warn!("addr_rm 192.168.4.1 returned false");
        }
        to_result_void(unsafe {
            net_mgmt_NET_REQUEST_WIFI_AP_DISABLE(0, iface, core::ptr::null_mut(), 0)
        })
    }

    /// Explicit /24 route on the AP iface — without this, the longest-prefix-match
    /// route lookup matches a /0 default route (e.g. PPP on walter) before the
    /// onlink-subnet check, and DNAT'd replies to STAs get routed back out the
    /// default iface instead of the AP iface.
    fn install_subnet_route() -> zephyr::Result<()> {
        let iface = unsafe { net_if_get_wifi_sap() };
        if iface.is_null() {
            return to_result_void(ENODEV);
        }
        let gw = unsafe { net_if_ipv4_get_gw(iface) };
        if unsafe { net_ipv4_is_addr_unspecified(&gw) } {
            return to_result_void(EAGAIN);
        }
        let gw_bytes: [u8; 4] = unsafe { *(&gw as *const _ as *const [u8; 4]) };
        let mut subnet = super::in_addr_v4([gw_bytes[0], gw_bytes[1], gw_bytes[2], 0]);
        let entry = unsafe {
            net_route_ipv4_add(
                iface,
                &mut subnet,
                24,
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

    fn dhcpv4_server_start() -> zephyr::Result<()> {
        let iface = unsafe { net_if_get_wifi_sap() };
        if iface.is_null() {
            return to_result_void(ENODEV);
        }
        let mut ap_addr = super::in_addr_v4(AP_IPV4);
        let netmask = super::in_addr_v4(AP_NETMASK);
        let mut pool_base = super::in_addr_v4(AP_POOL_START);
        to_result_void(unsafe {
            net_if_ipv4_set_gw(iface, &ap_addr);
            net_if_ipv4_addr_add(iface, &mut ap_addr, net_addr_type_NET_ADDR_MANUAL, 0);
            net_if_ipv4_set_netmask_by_addr(iface, &ap_addr, &netmask);
            net_dhcpv4_server_start(iface, &mut pool_base)
        })
    }
}

pub mod sta {
    use super::*;

    fn install_default_route() -> zephyr::Result<()> {
        let iface = unsafe { net_if_get_first_wifi() };
        if iface.is_null() {
            return to_result_void(ENODEV);
        }
        let mut gw = unsafe { net_if_ipv4_get_gw(iface) };
        if unsafe { net_ipv4_is_addr_unspecified(&gw) } {
            return to_result_void(EAGAIN);
        }
        let mut default_dst = super::in_addr_v4([0, 0, 0, 0]);
        let entry = unsafe {
            net_route_ipv4_add(
                iface,
                &mut default_dst,
                0,
                &mut gw,
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

    const STA_CONNECT_TIMEOUT_SECS: u64 = 30;

    pub fn initialize() -> zephyr::Result<()> {
        connect()?;
        match wait_for_ipv4(Duration::secs(STA_CONNECT_TIMEOUT_SECS)) {
            Ok(()) => Ok(()),
            Err(e) => {
                warn!("sta wait_for_ipv4: {e} — falling back to AP for provisioning");
                if let Err(ape) = super::ap::initialize() {
                    warn!("ap fallback: {ape}");
                } else {
                    super::ap::start_fallback_watchdog();
                }
                Err(e)
            }
        }
    }

    fn connect() -> zephyr::Result<()> {
        let iface = unsafe { net_if_get_first_wifi() };
        if iface.is_null() {
            return to_result_void(ENODEV);
        }
        to_result_void(unsafe {
            net_mgmt_NET_REQUEST_WIFI_CONNECT_STORED(0, iface, core::ptr::null_mut(), 0)
        })
    }

    pub fn is_connected() -> bool {
        let iface = unsafe { net_if_get_first_wifi() };
        if iface.is_null() {
            return false;
        }
        unsafe { !net_if_ipv4_get_global_addr(iface, net_addr_state_NET_ADDR_PREFERRED).is_null() }
    }

    pub(super) fn wait_for_ipv4(timeout: Duration) -> zephyr::Result<()> {
        if is_connected() {
            return Ok(());
        }
        let timeout_ms = timeout.to_millis() as u32;
        let poll_ms: u32 = 500;
        let mut waited: u32 = 0;
        while waited < timeout_ms {
            if is_connected() {
                info!("IPv4 up after {} ms", waited);
                if let Err(e) = install_default_route() {
                    warn!("wifi default route: {e}");
                }
                return Ok(());
            }
            zephyr::time::sleep(Duration::millis(poll_ms as u64));
            waited += poll_ms;
        }
        warn!("no wifi IPv4 after {} ms", timeout_ms);
        to_result_void(ETIMEDOUT)
    }
}
