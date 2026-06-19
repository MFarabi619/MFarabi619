#![no_std]
#![allow(unexpected_cfgs)]

extern crate alloc;

use firmware::programs::shell;

#[cfg(all(CONFIG_HTTP_SERVER, not(CONFIG_ZTEST)))]
use firmware::services::http;

#[cfg(not(CONFIG_ZTEST))]
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

    if let Err(e) = shell::initialize() {
        warn!("shell: {e}");
    }

    #[cfg(CONFIG_SQLITE)]
    {
        let version = unsafe {
            core::ffi::CStr::from_ptr(firmware::programs::sqlite::bindings::sqlite3_libversion())
        };
        info!("Rust sees SQLite {}", version.to_string_lossy());
        for path in ["/lfs/sqlite.db", "/RAM:/sqlite.db", "/ext2/sqlite.db"] {
            info!("--- smoke test on {} ---", path);
            if let Err(e) = sqlite_smoke_test(path) {
                warn!("sqlite smoke test on {}: {:?}", path, e);
            }
        }
    }
}

#[cfg(all(CONFIG_SQLITE, not(CONFIG_ZTEST)))]
fn sqlite_smoke_test(path: &str) -> Result<(), firmware::programs::sqlite::ResultCode> {
    use alloc::ffi::CString;
    use firmware::programs::sqlite::{self, Connection, ResultCode};

    let c_path = CString::new(path).unwrap();
    let db = sqlite::open(c_path.as_ptr())?;
    db.exec_safe(
        "CREATE TABLE IF NOT EXISTS readings (
            id INTEGER PRIMARY KEY, temperature REAL, label TEXT)",
    )?;
    db.exec_safe("DELETE FROM readings")?;
    db.exec_safe("INSERT INTO readings (temperature, label) VALUES (21.5, 'kitchen')")?;
    db.exec_safe("INSERT INTO readings (temperature, label) VALUES (19.0, 'outside')")?;

    let stmt = db.prepare_v2("SELECT id, temperature, label FROM readings")?;
    while stmt.step()? == ResultCode::ROW {
        let id = stmt.column_int64(0);
        let temp = stmt.column_double(1);
        let label = stmt.column_text(2)?;
        info!("row: id={} temp={} label={}", id, temp, label);
    }
    Ok(())
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
