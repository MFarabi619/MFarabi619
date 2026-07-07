#![no_std]
#![allow(unexpected_cfgs)]

use core::ffi::CStr;

use log::info;

// Force-link: only the C shell/ztests reference its `#[no_mangle]` symbols.
extern crate zephyr_lib_sqlite;

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }

    #[cfg(CONFIG_ZTEST)]
    unsafe {
        extern "C" {
            fn test_main();
        }
        test_main();
    }

    #[cfg(not(CONFIG_ZTEST))]
    {
        let version = unsafe { CStr::from_ptr(zephyr_lib_sqlite::bindings::sqlite3_libversion()) };
        info!(
            "SQLite {} via Rust bindings on {}",
            version.to_str().unwrap_or("?"),
            zephyr::kconfig::CONFIG_BOARD
        );
    }
}
