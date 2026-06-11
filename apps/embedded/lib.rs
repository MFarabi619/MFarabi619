#![no_std]

use log::{info, warn};

use firmware::boot;

cfg_if::cfg_if! {
    if #[cfg(CONFIG_MODEM_CELLULAR)] {
        mod walter;
    } else {
        mod xiao;
    }
}

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }

    info!("rust_main on {}", zephyr::kconfig::CONFIG_BOARD);

    cfg_if::cfg_if! {
        if #[cfg(CONFIG_MODEM_CELLULAR)] {
            walter::run();
        } else {
            xiao::run();
        }
    }

    if !boot::is_confirmed() {
        match boot::confirm() {
            Ok(()) => info!("boot: image confirmed"),
            Err(e) => warn!("boot confirm: {e}"),
        }
    }
}
