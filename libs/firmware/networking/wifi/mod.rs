use core::ffi::c_void;
use zephyr::{
    raw::{
        net_addr_state_NET_ADDR_PREFERRED, net_addr_type_NET_ADDR_MANUAL,
        net_dhcpv4_server_start, net_if_get_first_wifi, net_if_get_wifi_sap,
        net_if_ipv4_addr_add, net_if_ipv4_get_global_addr, net_if_ipv4_set_gw,
        net_if_ipv4_set_netmask_by_addr, net_in_addr,
        net_mgmt_NET_REQUEST_WIFI_AP_ENABLE, net_mgmt_NET_REQUEST_WIFI_CONNECT_STORED,
        wifi_connect_req_params, wifi_frequency_bands_WIFI_FREQ_BAND_2_4_GHZ,
        wifi_mfp_options_WIFI_MFP_OPTIONAL, wifi_security_type_WIFI_SECURITY_TYPE_NONE,
        wifi_security_type_WIFI_SECURITY_TYPE_PSK,
    },
    time::Duration,
};

use log::{info, warn};

use crate::utils::errno::{Errno, IntoResult};

const WIFI_CHANNEL_ANY: u8 = 255;
const ENODEV: i32 = -19;
const ETIMEDOUT: i32 = -110;

/// Default AP password used when no explicit password is supplied.
/// Anyone joining either board's AP uses this; xiao's STA static credentials
/// reach walter via this same secret.
pub const DEFAULT_AP_PASSWORD: &str = "pingmemaybe";

// net_route_ipv4_add lives in private subsys/net/ip headers (not in zephyr-sys
// bindings). Keep a one-function C shim for the default-route install.
extern "C" {
    fn wifi_sta_install_default_route() -> i32;
}

fn in_addr_v4(bytes: [u8; 4]) -> net_in_addr {
    let mut addr: net_in_addr = unsafe { core::mem::zeroed() };
    unsafe { *(&mut addr as *mut _ as *mut [u8; 4]) = bytes };
    addr
}

pub mod ap {
    use super::*;

    pub fn enable(ssid: &str, psk: &str) -> Result<(), Errno> {
        // IP / gateway / netmask + DHCP server must be configured BEFORE the AP
        // radio is enabled. Otherwise Zephyr brings the iface up with whatever
        // defaults NET_REQUEST_WIFI_AP_ENABLE puts in place, and clients that
        // associate before our gw/netmask call lands DHCP a broken lease (no
        // gateway → "connected, no internet").
        match dhcpv4_server_start() {
            Ok(()) => info!("ap: dhcpv4 server up on 192.168.4.1/24"),
            Err(e) => warn!("ap: dhcpv4 server start {e}"),
        }

        let iface = unsafe { net_if_get_wifi_sap() };
        if iface.is_null() {
            return ENODEV.ok();
        }

        let mut params: wifi_connect_req_params = unsafe { core::mem::zeroed() };
        params.ssid = ssid.as_ptr();
        params.ssid_length = ssid.len() as u8;
        if psk.is_empty() {
            // ESP HAL rejects WIFI_SECURITY_TYPE_PSK with a zero-length PSK
            // (ESP_ERR_WIFI_PASSWORD = 12299). Open AP for provisioning.
            params.security = wifi_security_type_WIFI_SECURITY_TYPE_NONE;
        } else {
            params.psk = psk.as_ptr();
            params.psk_length = psk.len() as u8;
            params.security = wifi_security_type_WIFI_SECURITY_TYPE_PSK;
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
