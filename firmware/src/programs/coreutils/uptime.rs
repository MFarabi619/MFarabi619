use core::fmt::Write;
use alloc::string::String as AllocString;
use embassy_time::Instant;

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let secs = Instant::now().as_secs();
    let _ = write!(out, "{}h {}m {}s\r\n", secs / 3600, (secs % 3600) / 60, secs % 60);
    out
}
