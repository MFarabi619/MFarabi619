pub fn now_stamp() -> (i32, u32) {
    oxidros::clock::Clock::new()
        .unwrap()
        .get_now()
        .map(|elapsed| (elapsed.as_secs() as i32, elapsed.subsec_nanos()))
        .unwrap_or_default()
}
