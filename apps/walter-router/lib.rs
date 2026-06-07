#![no_std]

use log::{info, warn};

use firmware::{
    networking::{cellular, dns, nat, wifi},
    utils::errno::{Errno, IntoResult},
};

extern "C" {
    fn boot_is_img_confirmed() -> bool;
    fn boot_write_img_confirmed() -> i32;
}

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }
    let board = zephyr::kconfig::CONFIG_BOARD;
    info!("rust_main on {board}");

    confirm_image();

    if let Err(e) = bring_up_cellular_stack() {
        warn!("cellular stack: {e}");
    }

    if let Err(e) = wifi::ap::enable(
        zephyr::kconfig::CONFIG_WIFI_CREDENTIALS_AP_SSID,
        zephyr::kconfig::CONFIG_WIFI_CREDENTIALS_AP_PASSWORD,
    ) {
        warn!("wifi ap: {e}");
    }
}

fn confirm_image() {
    if unsafe { boot_is_img_confirmed() } {
        return;
    }
    match unsafe { boot_write_img_confirmed() }.ok() {
        Ok(()) => info!("mcuboot: image confirmed"),
        Err(e) => warn!("mcuboot: image confirm failed: {e}"),
    }
}

fn bring_up_cellular_stack() -> Result<(), Errno> {
    use core::time::Duration;
    let timeout = Duration::from_millis(zephyr::kconfig::CONFIG_CELLULAR_ATTACH_TIMEOUT_MS as u64);

    cellular::initialize()?;
    cellular::wait_for_attach(timeout)?;
    for (label, value) in cellular::access_identity().iter() {
        if !value.is_empty() {
            info!("{label}: {value}");
        }
    }
    if let Err(e) = cellular::initialize_callbacks() {
        warn!("cellular: registration init failed: {e}");
    }
    nat::initialize()?;
    dns::initialize()?;
    Ok(())
}
