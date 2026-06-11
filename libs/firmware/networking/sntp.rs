use crate::utils::errno::{Errno, IntoResult};
use core::ffi::{c_char, c_int, CStr};

#[repr(C)]
struct SntpTime {
    seconds: u64,
    fraction: u32,
    rsp_delay_us: u32,
}

#[repr(C)]
struct Timespec {
    tv_sec: i64,
    tv_nsec: i32,
}

const SYS_CLOCK_REALTIME: c_int = 1;

unsafe extern "C" {
    fn sntp_simple(server: *const c_char, timeout_ms: u32, time: *mut SntpTime) -> c_int;
    #[link_name = "sys_clock_settime__extern"]
    fn sys_clock_settime(clock_id: c_int, tp: *const Timespec) -> c_int;
}

pub fn sync(server: &CStr, timeout_ms: u32) -> Result<(), Errno> {
    let mut ts = SntpTime { seconds: 0, fraction: 0, rsp_delay_us: 0 };
    unsafe { sntp_simple(server.as_ptr(), timeout_ms, &mut ts) }.ok()?;
    let tp = Timespec {
        tv_sec: ts.seconds as i64,
        tv_nsec: (((ts.fraction as u64) * 1_000_000_000_u64) >> 32) as i32,
    };
    unsafe { sys_clock_settime(SYS_CLOCK_REALTIME, &tp) }.ok()
}
