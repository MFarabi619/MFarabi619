#![no_std]

use log::{info, warn};

use firmware::networking::{wifi, wireguard};

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }

    info!("rust_main on {}", zephyr::kconfig::CONFIG_BOARD);

    if let Err(e) = wifi::sta::connect() {
        warn!("wifi sta: {e}");
    }

    if let Err(e) = wireguard::initialize() {
        warn!("wireguard: {e}");
    }
}
