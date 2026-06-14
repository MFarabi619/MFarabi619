use core::{
    cell::UnsafeCell,
    ffi::{c_char, c_void},
    mem::MaybeUninit,
};
use zephyr::{
    raw::{
        net_addr_state_NET_ADDR_PREFERRED, net_addr_type_NET_ADDR_MANUAL, net_dhcpv4_server_start,
        net_dhcpv4_server_stop, net_if, net_if_get_first_wifi, net_if_get_wifi_sap,
        net_if_ipv4_addr_add, net_if_ipv4_addr_rm, net_if_ipv4_get_global_addr,
        net_if_ipv4_set_gw, net_if_ipv4_set_netmask_by_addr, net_in_addr,
        net_mgmt_NET_REQUEST_WIFI_AP_DISABLE, net_mgmt_NET_REQUEST_WIFI_AP_ENABLE,
        net_mgmt_NET_REQUEST_WIFI_CONNECT_STORED, net_mgmt_add_event_callback,
        net_mgmt_del_event_callback, net_mgmt_event_callback, net_mgmt_init_event_callback,
        wifi_connect_req_params, wifi_credentials_get_by_ssid_personal_struct,
        wifi_credentials_personal, wifi_frequency_bands_WIFI_FREQ_BAND_2_4_GHZ,
        wifi_mfp_options_WIFI_MFP_OPTIONAL, wifi_security_type_WIFI_SECURITY_TYPE_NONE,
        ZR_NET_EVENT_IPV4_DHCP_BOUND,
    },
    time::Duration,
};

use log::{info, warn};

use crate::utils::errno::{Errno, IntoResult};

const WIFI_CHANNEL_ANY: u8 = 255;
const ENODEV: i32 = -19;
const ETIMEDOUT: i32 = -110;

extern "C" {
    fn wifi_sta_install_default_route() -> i32;
    fn wifi_ap_install_subnet_route() -> i32;
}

fn in_addr_v4(bytes: [u8; 4]) -> net_in_addr {
    let mut addr: net_in_addr = unsafe { core::mem::zeroed() };
    unsafe { *(&mut addr as *mut _ as *mut [u8; 4]) = bytes };
    addr
}

struct CbCell(UnsafeCell<MaybeUninit<net_mgmt_event_callback>>);
unsafe impl Sync for CbCell {}
static FALLBACK_AP_CB: CbCell = CbCell(UnsafeCell::new(MaybeUninit::uninit()));

unsafe extern "C" fn on_dhcp_bound(
    cb: *mut net_mgmt_event_callback,
    _event: u64,
    iface: *mut net_if,
) {
    if iface == unsafe { net_if_get_wifi_sap() } {
        return;
    }
    info!("ap: STA got IP — tearing down fallback AP");
    let _ = ap::disable();
    unsafe { net_mgmt_del_event_callback(cb) };
}

/// Fallback AP at 192.168.4.1/wlan1 conflicts with the peer-AP subnet on STA,
/// stalling DHCP in `selecting`. Disable the AP the moment STA gets a lease.
pub fn arm_fallback_ap_watchdog() {
    unsafe {
        let cb = (*FALLBACK_AP_CB.0.get()).as_mut_ptr();
        net_mgmt_init_event_callback(cb, Some(on_dhcp_bound), ZR_NET_EVENT_IPV4_DHCP_BOUND);
        net_mgmt_add_event_callback(cb);
    }
}

pub mod ap {
    use super::*;

    /// SSID = hostname; PSK comes from wifi_credentials by SSID, open AP if unset.
    pub fn enable() -> Result<(), Errno> {
        let ssid = zephyr::kconfig::CONFIG_NET_HOSTNAME;

        let mut creds: wifi_credentials_personal = unsafe { core::mem::zeroed() };
        let cred_rc = unsafe {
            wifi_credentials_get_by_ssid_personal_struct(
                ssid.as_ptr() as *const c_char,
                ssid.len(),
                &mut creds,
            )
        };

        // Must run BEFORE AP_ENABLE: clients that associate before the gw/netmask
        // call lands get a broken DHCP lease (no gateway).
        match dhcpv4_server_start() {
            Ok(()) => info!("ap: dhcpv4 server up on 192.168.4.1/24"),
            Err(e) => warn!("ap: dhcpv4 server start {e}"),
        }

        if let Err(e) = unsafe { wifi_ap_install_subnet_route() }.ok() {
            warn!("ap subnet route: {e}");
        }

        let iface = unsafe { net_if_get_wifi_sap() };
        if iface.is_null() {
            return ENODEV.ok();
        }

        let mut params: wifi_connect_req_params = unsafe { core::mem::zeroed() };
        params.ssid = ssid.as_ptr();
        params.ssid_length = ssid.len() as u8;
        if cred_rc != 0 || creds.password_len == 0 {
            if cred_rc != 0 && cred_rc != -2 /* -ENOENT */ {
                warn!("ap cred load: errno {cred_rc}");
            }
            info!("ap: no stored cred for '{ssid}' — open AP for provisioning");
            params.security = wifi_security_type_WIFI_SECURITY_TYPE_NONE;
        } else {
            info!("ap: using stored cred for '{ssid}'");
            params.psk = creds.password.as_ptr() as *const u8;
            params.psk_length = creds.password_len as u8;
            params.security = creds.header.type_ as u32;
            params.mfp = wifi_mfp_options_WIFI_MFP_OPTIONAL;
        }
        params.channel = WIFI_CHANNEL_ANY;
        params.band = wifi_frequency_bands_WIFI_FREQ_BAND_2_4_GHZ as u8;

        unsafe {
            net_mgmt_NET_REQUEST_WIFI_AP_ENABLE(
                0,
                iface,
                &mut params as *mut _ as *mut c_void,
                core::mem::size_of::<wifi_connect_req_params>(),
            )
        }
        .ok()?;
        info!("ap: enabled ssid={ssid}");

        #[cfg(CONFIG_MCUMGR_TRANSPORT_UDP)]
        match crate::services::mcumgr::udp_open() {
            Ok(()) => info!("mcumgr: udp listening"),
            Err(e) => warn!("mcumgr udp: {e}"),
        }
        Ok(())
    }

    pub fn disable() -> Result<(), Errno> {
        let iface = unsafe { net_if_get_wifi_sap() };
        if iface.is_null() {
            return ENODEV.ok();
        }
        let rc = unsafe { net_dhcpv4_server_stop(iface) };
        if rc != 0 && rc != -2 /* -ENOENT */ {
            warn!("ap: dhcpv4 server stop: {rc}");
        }
        let ap_addr = super::in_addr_v4([192, 168, 4, 1]);
        if !unsafe { net_if_ipv4_addr_rm(iface, &ap_addr) } {
            warn!("ap: addr_rm 192.168.4.1 returned false");
        }
        unsafe {
            net_mgmt_NET_REQUEST_WIFI_AP_DISABLE(0, iface, core::ptr::null_mut(), 0)
        }
        .ok()
    }

    fn dhcpv4_server_start() -> Result<(), Errno> {
        let iface = unsafe { net_if_get_wifi_sap() };
        if iface.is_null() {
            return ENODEV.ok();
        }
        let mut ap_addr   = super::in_addr_v4([192, 168, 4, 1]);
        let netmask       = super::in_addr_v4([255, 255, 255, 0]);
        let mut pool_base = super::in_addr_v4([192, 168, 4, 11]);
        unsafe {
            net_if_ipv4_set_gw(iface, &ap_addr);
            net_if_ipv4_addr_add(iface, &mut ap_addr, net_addr_type_NET_ADDR_MANUAL, 0);
            net_if_ipv4_set_netmask_by_addr(iface, &ap_addr, &netmask);
            net_dhcpv4_server_start(iface, &mut pool_base)
        }
        .ok()
    }
}

pub mod sta {
    use super::*;

    pub fn connect() -> Result<(), Errno> {
        let iface = unsafe { net_if_get_first_wifi() };
        if iface.is_null() {
            return ENODEV.ok();
        }
        unsafe { net_mgmt_NET_REQUEST_WIFI_CONNECT_STORED(0, iface, core::ptr::null_mut(), 0) }.ok()
    }

    pub fn is_connected() -> bool {
        let iface = unsafe { net_if_get_first_wifi() };
        if iface.is_null() {
            return false;
        }
        unsafe { !net_if_ipv4_get_global_addr(iface, net_addr_state_NET_ADDR_PREFERRED).is_null() }
    }

    pub fn wait_for_ipv4(timeout: Duration) -> Result<(), Errno> {
        if is_connected() {
            return Ok(());
        }
        let timeout_ms = timeout.to_millis() as u32;
        let poll_ms: u32 = 500;
        let mut waited: u32 = 0;
        while waited < timeout_ms {
            if is_connected() {
                info!("IPv4 up after {} ms", waited);
                if let Err(e) = unsafe { wifi_sta_install_default_route() }.ok() {
                    warn!("wifi default route: {e}");
                }
                match crate::networking::sntp::sync(
                    core::ffi::CStr::from_bytes_with_nul(b"pool.ntp.org\0").unwrap(),
                    5000,
                ) {
                    Ok(()) => info!("sntp: time synced"),
                    Err(e) => warn!("sntp: {e}"),
                }
                #[cfg(CONFIG_MCUMGR_TRANSPORT_UDP)]
                match crate::services::mcumgr::udp_open() {
                    Ok(()) => info!("mcumgr: udp listening"),
                    Err(e) => warn!("mcumgr udp: {e}"),
                }
                return Ok(());
            }
            zephyr::time::sleep(Duration::millis(poll_ms as u64));
            waited += poll_ms;
        }
        warn!("no wifi IPv4 after {} ms", timeout_ms);
        ETIMEDOUT.ok()
    }
}
