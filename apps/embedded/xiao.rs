use log::warn;
use zephyr::time::Duration;

use firmware::networking::{wifi, wireguard};

pub fn run() {
    if let Err(e) = wifi::sta::connect() {
        warn!("wifi sta: {e}");
    }

    match wifi::sta::wait_for_ipv4(Duration::secs(30)) {
        Ok(()) => {
            if let Err(e) = wireguard::initialize() {
                warn!("wireguard: {e}");
            }
        }
        Err(e) => {
            warn!("wifi sta wait_for_ipv4: {e} — falling back to AP for provisioning");
            if let Err(e) = wifi::ap::enable(
                zephyr::kconfig::CONFIG_WIFI_CREDENTIALS_AP_SSID,
                zephyr::kconfig::CONFIG_WIFI_CREDENTIALS_AP_PASSWORD,
            ) {
                warn!("wifi ap fallback: {e}");
            }
        }
    }
}
