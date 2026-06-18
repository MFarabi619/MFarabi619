use core::ffi::c_int;

unsafe extern "C" {
    fn http_server_start() -> c_int;
}

pub fn initialize() -> zephyr::Result<()> {
    zephyr::error::to_result_void(unsafe { http_server_start() })
}
