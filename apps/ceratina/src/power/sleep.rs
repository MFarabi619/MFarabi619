use core::sync::atomic::{AtomicBool, AtomicU32, AtomicU8, Ordering};

pub struct SleepSnapshot {
    pub pending: bool,
    pub requested_duration_seconds: u64,
    pub wake_cause: &'static str,
}

static PENDING: AtomicBool = AtomicBool::new(false);
static REQUESTED_DURATION_SECONDS: AtomicU32 = AtomicU32::new(0);
static WAKE_CAUSE_CODE: AtomicU8 = AtomicU8::new(0);

pub fn initialize() {
    PENDING.store(false, Ordering::Relaxed);
    REQUESTED_DURATION_SECONDS.store(0, Ordering::Relaxed);
}

pub fn request(duration_seconds: u64) -> bool {
    if duration_seconds == 0 || duration_seconds > u32::MAX as u64 {
        return false;
    }
    REQUESTED_DURATION_SECONDS.store(duration_seconds as u32, Ordering::Release);
    PENDING.store(true, Ordering::Release);
    true
}

pub fn cancel_request() {
    PENDING.store(false, Ordering::Relaxed);
    REQUESTED_DURATION_SECONDS.store(0, Ordering::Relaxed);
}

pub fn set_wake_cause(code: u8) {
    WAKE_CAUSE_CODE.store(code, Ordering::Release);
}

pub fn wake_cause() -> &'static str {
    match WAKE_CAUSE_CODE.load(Ordering::Acquire) {
        1 => "timer",
        2 => "gpio",
        3 => "ext0",
        4 => "ext1",
        _ => "power_on",
    }
}

pub fn snapshot() -> SleepSnapshot {
    SleepSnapshot {
        pending: PENDING.load(Ordering::Acquire),
        requested_duration_seconds: REQUESTED_DURATION_SECONDS.load(Ordering::Acquire) as u64,
        wake_cause: wake_cause(),
    }
}
