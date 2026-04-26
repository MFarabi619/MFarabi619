use alloc::string::String as AllocString;
use core::fmt::Write;

use crate::time;

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let epoch = time::get_current_epoch_secs();

    if epoch == 0 {
        let _ = write!(out, "\x1b[2mtime not synced\x1b[0m\r\n");
    } else {
        let _ = write!(out, "{}\r\n", time::format_iso8601(epoch));
    }

    out
}
