extern "C" {
    fn wifi_ap_enable(
        ssid: *const u8,
        ssid_len: usize,
        psk: *const u8,
        psk_len: usize,
    ) -> i32;
    fn wifi_ap_dhcpv4_server_start() -> i32;
    fn wifi_sta_connect_stored() -> i32;
    fn wifi_sta_has_ipv4() -> bool;
}

pub mod ap {
    use super::{wifi_ap_dhcpv4_server_start, wifi_ap_enable};
    use crate::utils::errno::{Errno, IntoResult};
    use log::{info, warn};

    pub fn enable(ssid: &str, psk: &str) -> Result<(), Errno> {
        // IP / gateway / netmask + DHCP server must be configured BEFORE the AP
        // radio is enabled. Otherwise Zephyr brings the iface up with whatever
        // defaults NET_REQUEST_WIFI_AP_ENABLE puts in place, and clients that
        // associate before our gw/netmask call lands DHCP a broken lease (no
        // gateway → "connected, no internet").
        match unsafe { wifi_ap_dhcpv4_server_start() }.ok() {
            Ok(()) => info!("ap: dhcpv4 server up on 192.168.4.1/24"),
            Err(e) => warn!("ap: dhcpv4 server start {e}"),
        }
        unsafe { wifi_ap_enable(ssid.as_ptr(), ssid.len(), psk.as_ptr(), psk.len()) }.ok()?;
        info!("ap: enabled ssid={ssid}");
        Ok(())
    }
}

pub mod sta {
    use super::{wifi_sta_connect_stored, wifi_sta_has_ipv4};
    use crate::utils::errno::{Errno, IntoResult};
    use core::time::Duration;
    use log::{info, warn};

    pub fn connect() -> Result<(), Errno> {
        unsafe { wifi_sta_connect_stored() }.ok()
    }

    pub fn is_connected() -> bool {
        unsafe { wifi_sta_has_ipv4() }
    }

    pub fn wait_for_ipv4(timeout: Duration) -> Result<(), Errno> {
        let timeout_ms = timeout.as_millis() as u32;
        let poll_ms: u32 = 500;
        let mut waited: u32 = 0;
        while waited < timeout_ms {
            if is_connected() {
                info!("wifi IPv4 up after {} ms", waited);
                return Ok(());
            }
            zephyr::time::sleep(zephyr::time::Duration::millis(poll_ms as u64));
            waited += poll_ms;
        }
        warn!("no wifi IPv4 after {} ms", timeout_ms);
        (-110_i32).ok()
    }
}
