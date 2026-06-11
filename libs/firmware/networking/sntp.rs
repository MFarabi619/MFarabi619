use crate::utils::errno::{Errno, IntoResult};
use core::ffi::{c_int, CStr};
use zephyr::raw::{sntp_simple, sntp_time, sys_clock_settime, timespec};

const SYS_CLOCK_REALTIME: c_int = 1;

pub fn sync(server: &CStr, timeout_ms: u32) -> Result<(), Errno> {
    let mut ts = sntp_time::default();
    unsafe { sntp_simple(server.as_ptr(), timeout_ms, &mut ts) }.ok()?;
    let tp = timespec {
        tv_sec: ts.seconds as _,
        tv_nsec: (((ts.fraction as u64) * 1_000_000_000_u64) >> 32) as _,
    };
    unsafe { sys_clock_settime(SYS_CLOCK_REALTIME, &tp) }.ok()
}
