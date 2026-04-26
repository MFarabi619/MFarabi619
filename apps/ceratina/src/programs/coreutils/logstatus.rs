use alloc::string::String as AllocString;
use core::fmt::Write;

use crate::services::system;

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let snapshot = system::snapshot();
    let _ = write!(
        out,
        "path={}\r\ninterval_seconds={}\r\n",
        snapshot.data_logger.path, snapshot.data_logger.interval_seconds
    );
    out
}
