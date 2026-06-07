use log::{info, warn};

use crate::utils::errno::{Errno, IntoResult};

extern "C" {
    fn wifiAPEnable(
        ssid: *const u8,
        ssid_len: usize,
        psk: *const u8,
        psk_len: usize,
    ) -> i32;
    fn wifiAPDHCPv4ServerStart() -> i32;
    fn wifiSTAConnectStored() -> i32;
}

pub fn enable_ap(ssid: &str, psk: &str) -> Result<(), Errno> {
    // IP / gateway / netmask + DHCP server must be configured BEFORE the AP
    // radio is enabled. Otherwise Zephyr brings the iface up with whatever
    // defaults `NET_REQUEST_WIFI_AP_ENABLE` puts in place, and clients that
    // associate before our gw/netmask call lands DHCP a broken lease (no
    // gateway → "connected, no internet").
    match unsafe { wifiAPDHCPv4ServerStart() }.ok() {
        Ok(()) => info!("ap: dhcpv4 server up on 192.168.4.1/24"),
        Err(e) => warn!("ap: dhcpv4 server start {e}"),
    }

    unsafe { wifiAPEnable(ssid.as_ptr(), ssid.len(), psk.as_ptr(), psk.len()) }.ok()?;
    info!("ap: enabled ssid={ssid}");
    Ok(())
}

pub fn sta_connect_stored() -> Result<(), Errno> {
    unsafe { wifiSTAConnectStored() }.ok()
}
