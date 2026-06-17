#![no_std]

extern crate alloc;

use firmware::shell;

use log::{info, warn};

#[cfg(all(CONFIG_NETWORKING, dt = "labels::modem"))]
use firmware::networking::{cellular, dns, nat, wifi};

#[cfg(all(CONFIG_NETWORKING, not(dt = "labels::modem")))]
use firmware::networking::wifi;

#[cfg(all(CONFIG_NETWORKING, not(dt = "labels::modem"), CONFIG_WIREGUARD))]
use firmware::networking::wireguard;

#[cfg(CONFIG_BOOTLOADER_MCUBOOT)]
use zephyr::{
    error::to_result_void,
    raw::{boot_is_img_confirmed, boot_write_img_confirmed},
};

#[cfg(CONFIG_FS_FATFS_HAS_RTC)]
#[no_mangle]
extern "C" fn get_fattime() -> u32 {
    let mut wall_clock = shell::Timespec::default();
    if unsafe { shell::sys_clock_gettime(1, &mut wall_clock) } != 0
        || wall_clock.tv_sec < 1_577_836_800
    {
        return 0;
    }
    wall_clock.tv_sec += (zephyr::kconfig::CONFIG_PROMPT_TZ_OFFSET_MINUTES as i64) * 60;
    let mut calendar = shell::Tm::default();
    unsafe { shell::gmtime_r(&wall_clock.tv_sec, &mut calendar) };
    ((calendar.tm_year - 80) as u32) << 25
        | ((calendar.tm_mon + 1) as u32) << 21
        | (calendar.tm_mday as u32) << 16
        | (calendar.tm_hour as u32) << 11
        | (calendar.tm_min as u32) << 5
        | ((calendar.tm_sec / 2) as u32)
}

#[cfg(target_arch = "xtensa")]
use core::ffi::c_int;
#[cfg(target_arch = "xtensa")]
use zephyr::raw::init_entry;

#[cfg(target_arch = "xtensa")]
unsafe extern "C" {
    fn esp_flash_app_init();
    fn esp_flash_init_default_chip() -> c_int;
}

#[cfg(target_arch = "xtensa")]
unsafe extern "C" fn flash_default_chip_init() -> c_int {
    unsafe {
        esp_flash_app_init();
        esp_flash_init_default_chip();
    }
    0
}

#[cfg(target_arch = "xtensa")]
#[repr(transparent)]
struct InitEntry(#[allow(dead_code)] init_entry);
#[cfg(target_arch = "xtensa")]
unsafe impl Sync for InitEntry {}

#[cfg(target_arch = "xtensa")]
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

    #[cfg(all(CONFIG_NETWORKING, dt = "labels::modem"))]
    router();

    #[cfg(all(CONFIG_NETWORKING, not(dt = "labels::modem")))]
    node();

    #[cfg(CONFIG_BOOTLOADER_MCUBOOT)]
    if !unsafe { boot_is_img_confirmed() } {
        match to_result_void(unsafe { boot_write_img_confirmed() }) {
            Ok(()) => info!("boot: image confirmed"),
            Err(e) => warn!("boot confirm: {e}"),
        }
    }

    if let Err(e) = shell::initialize() {
        warn!("shell: {e}");
    }
}

#[cfg(all(CONFIG_NETWORKING, dt = "labels::modem"))]
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

#[cfg(all(CONFIG_NETWORKING, not(dt = "labels::modem")))]
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
