use crate::services::identity;
use alloc::string::String as AllocString;
use core::fmt::Write;

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let _ = write!(out, "{}\r\n", identity::hostname());
    out
}
