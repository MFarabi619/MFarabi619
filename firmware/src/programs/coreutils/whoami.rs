use core::fmt::Write;
use alloc::string::String as AllocString;
use crate::programs::shell;

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let _ = write!(out, "{}\r\n", shell::SSH_USER);
    out
}
