use core::ffi::{c_char, c_void, CStr};

extern "C" {
    fn shell_backend_uart_get_ptr() -> *const c_void;
    fn shell_prompt_change(sh: *const c_void, prompt: *const c_char) -> i32;
}

pub fn set_prompt(prompt: &CStr) -> zephyr::Result<()> {
    let sh = unsafe { shell_backend_uart_get_ptr() };
    if sh.is_null() {
        return zephyr::error::to_result_void(-19);
    }
    zephyr::error::to_result_void(unsafe { shell_prompt_change(sh, prompt.as_ptr()) })
}
