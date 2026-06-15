#![no_std]

extern crate alloc;

pub mod icons;
pub mod prompt;
pub mod shell;

pub mod networking;

use log::{info, warn};
use zephyr::{
    error::to_result_void,
    raw::{boot_is_img_confirmed, boot_write_img_confirmed},
};

#[cfg(dt = "labels::modem")]
use crate::networking::{cellular, dns, nat, wifi};

#[cfg(not(dt = "labels::modem"))]
use crate::networking::wifi;

#[cfg(all(not(dt = "labels::modem"), CONFIG_WIREGUARD))]
use crate::networking::wireguard;

use core::ffi::c_int;
use zephyr::raw::init_entry;

unsafe extern "C" {
    fn esp_flash_app_init();
    fn esp_flash_init_default_chip() -> c_int;
}

unsafe extern "C" fn flash_default_chip_init() -> c_int {
    unsafe {
        esp_flash_app_init();
        esp_flash_init_default_chip();
    }
    0
}

#[repr(transparent)]
struct InitEntry(#[allow(dead_code)] init_entry);
unsafe impl Sync for InitEntry {}

#[used]
#[link_section = ".z_init_POST_KERNEL_P_99_SUB_0_"]
static FLASH_INIT_ENTRY: InitEntry = InitEntry(init_entry {
    init_fn: Some(flash_default_chip_init),
    dev: core::ptr::null(),
});

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }
    info!("rust_main on {}", zephyr::kconfig::CONFIG_BOARD);

    #[cfg(dt = "labels::modem")]
    router();

    #[cfg(not(dt = "labels::modem"))]
    node();

    if !unsafe { boot_is_img_confirmed() } {
        match to_result_void(unsafe { boot_write_img_confirmed() }) {
            Ok(()) => info!("boot: image confirmed"),
            Err(e) => warn!("boot confirm: {e}"),
        }
    }

    zephyr::time::sleep(zephyr::time::Duration::millis_at_least(200));
    shell::probe_terminal_size();
    let p = prompt::build_prompt();
    let _ = shell::set_prompt(p.as_c_str());
    shell::redraw_prompt();
}

#[cfg(dt = "labels::modem")]
fn router() {
    if let Err(e) = cellular::initialize() {
        warn!("cellular: {e}");
    }
    if let Err(e) = nat::initialize() {
        warn!("nat: {e}");
    }
    if let Err(e) = dns::initialize() {
        warn!("dns: {e}");
    }
    if let Err(e) = wifi::ap::initialize() {
        warn!("wifi ap: {e}");
    }
}

#[cfg(not(dt = "labels::modem"))]
fn node() {
    if let Err(e) = wifi::sta::initialize() {
        warn!("wifi sta: {e}");
        return;
    }
    #[cfg(CONFIG_WIREGUARD)]
    if let Err(e) = wireguard::initialize() {
        warn!("wireguard: {e}");
    }
}
