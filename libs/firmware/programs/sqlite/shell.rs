use alloc::ffi::CString;
use alloc::format;
use core::cell::UnsafeCell;
use core::ffi::{c_char, c_int, c_void, CStr};

use super::{bindings, open as sqlite_open, Connection, ManagedConnection, ResultCode};

struct DbCell(UnsafeCell<Option<ManagedConnection>>);
unsafe impl Sync for DbCell {}
static DB: DbCell = DbCell(UnsafeCell::new(None));

extern "C" {
    fn sqlite_shell_print_line(sh: *const c_void, line: *const c_char);
    fn sqlite_shell_error_line(sh: *const c_void, line: *const c_char);
}

fn print_line(sh: *const c_void, line: &str) {
    if let Ok(c_string) = CString::new(line) {
        unsafe { sqlite_shell_print_line(sh, c_string.as_ptr()) };
    }
}

fn error_line(sh: *const c_void, line: &str) {
    if let Ok(c_string) = CString::new(line) {
        unsafe { sqlite_shell_error_line(sh, c_string.as_ptr()) };
    }
}

#[no_mangle]
extern "C" fn rust_sqlite_open(sh: *const c_void, path: *const c_char) -> c_int {
    let db_slot = unsafe { &mut *DB.0.get() };
    *db_slot = None;

    match sqlite_open(path) {
        Ok(connection) => {
            let path_str = unsafe { CStr::from_ptr(path) }.to_string_lossy();
            print_line(sh, &format!("opened {path_str}"));
            *db_slot = Some(connection);
            0
        }
        Err(rc) => {
            error_line(sh, &format!("open failed: {rc:?}"));
            -5
        }
    }
}

#[no_mangle]
extern "C" fn rust_sqlite_close(sh: *const c_void) -> c_int {
    let db_slot = unsafe { &mut *DB.0.get() };
    if db_slot.is_none() {
        error_line(sh, "no database open");
        return 0;
    }
    *db_slot = None;
    print_line(sh, "closed");
    0
}

#[no_mangle]
extern "C" fn rust_sqlite_exec(sh: *const c_void, sql: *const c_char) -> c_int {
    let db_slot = unsafe { &mut *DB.0.get() };
    let database = match db_slot {
        Some(database) => database,
        None => {
            error_line(sh, "no database open (use `sqlite open <path>`)");
            return -2;
        }
    };

    let sql_str = match unsafe { CStr::from_ptr(sql) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            error_line(sh, "invalid UTF-8 in SQL");
            return -22;
        }
    };

    let statement = match database.prepare_v2(sql_str) {
        Ok(statement) => statement,
        Err(rc) => {
            error_line(sh, &format!("prepare: {rc:?}"));
            return -5;
        }
    };

    let column_count = statement.column_count();
    loop {
        match statement.step() {
            Ok(ResultCode::ROW) => {
                for index in 0..column_count {
                    let name = statement.column_name(index).unwrap_or("?");
                    let value = statement.column_text(index).unwrap_or("NULL");
                    print_line(sh, &format!("  {name} = {value}"));
                }
                print_line(sh, "---");
            }
            Ok(_) => break,
            Err(rc) => {
                error_line(sh, &format!("step: {rc:?}"));
                return -5;
            }
        }
    }
    0
}

#[no_mangle]
extern "C" fn rust_sqlite_version(sh: *const c_void) -> c_int {
    let version = unsafe { CStr::from_ptr(bindings::sqlite3_libversion()) };
    print_line(sh, &format!("SQLite {}", version.to_string_lossy()));
    0
}
