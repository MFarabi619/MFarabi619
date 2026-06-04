#![no_std]
#![allow(non_snake_case)]

use log::{info, warn};

mod cellular;

use firmware::networking::{dns, nat, wifi};
use firmware::utils::errno::{Errno, IntoResult};

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

    confirmImage();

    if let Err(e) = bringUpCellularStack() {
        warn!("cellular stack: {e}");
    }

    if let Err(e) = wifi::initialize() {
        warn!("wifi ap: {e}");
    }
}

fn confirmImage() {
    if unsafe { boot_is_img_confirmed() } {
        return;
    }
    match unsafe { boot_write_img_confirmed() }.ok() {
        Ok(()) => info!("mcuboot: image confirmed"),
        Err(e) => warn!("mcuboot: image confirm failed: {e}"),
    }
}

fn bringUpCellularStack() -> Result<(), Errno> {
    use core::time::Duration;
    let timeout = Duration::from_millis(zephyr::kconfig::CONFIG_CELLULAR_ATTACH_TIMEOUT_MS as u64);

    cellular::initialize()?;
    cellular::waitForAttach(timeout)?;
    for (label, value) in cellular::accessIdentity().iter() {
        if !value.is_empty() {
            info!("{label}: {value}");
        }
    }
    if let Err(e) = cellular::initializeCallbacks() {
        warn!("cellular: registration init failed: {e}");
    }
    nat::initialize()?;
    dns::initialize()?;
    Ok(())
}
