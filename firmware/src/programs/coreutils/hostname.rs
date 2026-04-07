use core::fmt::Write;
use alloc::string::String as AllocString;

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let _ = write!(out, "{}\r\n", crate::config::HOSTNAME);
    out
}
