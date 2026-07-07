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
        use zephyr_lib_sqlite::{open, Connection, ResultCode};

        let version = unsafe { CStr::from_ptr(zephyr_lib_sqlite::bindings::sqlite3_libversion()) };
        info!(
            "SQLite {} on {} — /lfs/demo.db",
            version.to_str().unwrap_or("?"),
            zephyr::kconfig::CONFIG_BOARD
        );

        let database = match open(c"/lfs/demo.db".as_ptr()) {
            Ok(database) => database,
            Err(rc) => {
                info!("open failed: {rc:?}");
                return;
            }
        };

        let _ = database.exec_safe("CREATE TABLE IF NOT EXISTS readings(sensor TEXT, value REAL)");
        let _ = database.exec_safe("DELETE FROM readings");
        let _ = database.exec_safe(
            "INSERT INTO readings VALUES('temp', 21.5), ('humidity', 48.0), ('pressure', 1013.2)",
        );

        let statement =
            match database.prepare_v2("SELECT sensor, value FROM readings ORDER BY sensor") {
                Ok(statement) => statement,
                Err(rc) => {
                    info!("prepare failed: {rc:?}");
                    return;
                }
            };

        while statement.step() == Ok(ResultCode::ROW) {
            let sensor = statement.column_text(0).unwrap_or("?");
            let value = statement.column_text(1).unwrap_or("?");
            info!("  {sensor} = {value}");
        }
    }
}
