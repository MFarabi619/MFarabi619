use std::time::{SystemTime, UNIX_EPOCH};

pub fn now_stamp() -> (i32, u32) {
    let since = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    (since.as_secs() as i32, since.subsec_nanos())
}
