use core::fmt::Write;
use alloc::string::String as AllocString;
use crate::filesystems::sd::delete_at;

pub fn run(cwd: &str, name: &str) -> AllocString {
    if name.is_empty() {
        return super::fmt_usage("rm <name>");
    }

    match delete_at(cwd, name) {
        Ok(()) => {
            let mut out = AllocString::new();
            let _ = write!(out, "removed {}\r\n", name);
            out
        }
        Err(error) => super::fmt_error(&error),
    }
}
