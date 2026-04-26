use alloc::string::String as AllocString;
use core::fmt::Write;

use crate::services::system;

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let snapshot = system::snapshot();
    let _ = write!(out, "{}\r\n", snapshot.sleep.wake_cause);
    out
}
