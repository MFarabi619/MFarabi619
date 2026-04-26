use core::fmt::Write;
use alloc::string::String as AllocString;
use crate::filesystems::sd::mkdir_at;

pub fn run(cwd: &str, name: &str) -> AllocString {
    if name.is_empty() {
        return super::fmt_usage("mkdir <name>");
    }

    match mkdir_at(cwd, name) {
        Ok(()) => {
            let mut out = AllocString::new();
            let _ = write!(out, "created {}\r\n", name);
            out
        }
        Err(error) => super::fmt_error(&error),
    }
}
