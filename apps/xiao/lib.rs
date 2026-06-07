#![no_std]

use log::{info, warn};

use firmware::{networking::wifi, services::tailscale};

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }

    info!("rust_main on {}", zephyr::kconfig::CONFIG_BOARD);

    if let Err(e) = wifi::sta_connect_stored() {
        warn!("wifi sta: {e}");
    }

    if let Err(e) = tailscale::start() {
        warn!("tailscale: {e}");
    }
}
