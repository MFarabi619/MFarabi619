#![no_std]
#![allow(unexpected_cfgs)]

extern crate alloc;

pub mod programs;
pub mod services;

#[cfg(CONFIG_NETWORKING)]
pub mod networking;

#[cfg(CONFIG_ZTEST)]
pub mod bdd {
    use alloc::ffi::CString;
    use core::ffi::c_char;

    extern "C" {
        fn printk(format: *const c_char, ...);
    }

    pub fn given(text: &str) {
        emit(
            text,
            c"  \x1b[1;30;46m[GIVEN]\x1b[0m \x1b[36m%s\x1b[0m\n".as_ptr(),
        );
    }

    pub fn when(text: &str) {
        emit(
            text,
            c"    \x1b[1;30;103m[WHEN]\x1b[0m \x1b[33m%s\x1b[0m\n".as_ptr(),
        );
    }

    pub fn then(text: &str) {
        emit(
            text,
            c"      \x1b[1;30;105m[THEN]\x1b[0m \x1b[35m%s\x1b[0m\n".as_ptr(),
        );
    }

    pub fn and(text: &str) {
        emit(
            text,
            c"      \x1b[1;30;105m[AND]\x1b[0m  \x1b[35m%s\x1b[0m\n".as_ptr(),
        );
    }

    fn emit(text: &str, format: *const c_char) {
        if let Ok(c_text) = CString::new(text) {
            unsafe { printk(format, c_text.as_ptr()) };
        }
    }
}

use crate::programs::shell;

#[cfg(all(CONFIG_HTTP_SERVER, not(CONFIG_ZTEST)))]
use crate::services::http;

#[cfg(not(CONFIG_ZTEST))]
use log::{info, warn};

#[cfg(all(CONFIG_NETWORKING, dt = "labels::modem"))]
use crate::networking::{cellular, dns, nat, wifi};

#[cfg(all(CONFIG_NETWORKING, not(dt = "labels::modem")))]
use crate::networking::wifi;

#[cfg(all(CONFIG_NETWORKING, not(dt = "labels::modem"), CONFIG_WIREGUARD))]
use crate::networking::wireguard;

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

#[cfg(CONFIG_ZTEST)]
#[no_mangle]
extern "C" fn rust_main() {
    extern "C" {
        fn test_main();
    }
    unsafe { test_main() };
}

#[cfg(not(CONFIG_ZTEST))]
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

    #[cfg(not(CONFIG_TEST))]
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
    #[cfg(CONFIG_HTTP_SERVER)]
    if let Err(e) = http::server::initialize() {
        warn!("http server: {e}");
    }
}
