#![no_std]

use log::{info, warn};
use zephyr::time::Duration;

use firmware::networking::{wifi, wireguard};
use firmware::boot;

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }

    info!("rust_main on {}", zephyr::kconfig::CONFIG_BOARD);

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

    match boot::confirm() {
        Ok(()) => info!("boot: image confirmed"),
        Err(e) => warn!("boot confirm: {e}"),
    }
}
