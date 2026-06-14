#![no_std]

use core::ffi::{c_char, c_void, CStr};

use log::info;

extern "C" {
    fn shell_backend_uart_get_ptr() -> *const c_void;
    fn shell_prompt_change(sh: *const c_void, prompt: *const c_char) -> i32;
}

fn set_prompt(prompt: &CStr) {
    let sh = unsafe { shell_backend_uart_get_ptr() };
    if sh.is_null() {
        return;
    }
    unsafe {
        shell_prompt_change(sh, prompt.as_ptr());
    }
}

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }
    info!("zephyr-qemu on {}", zephyr::kconfig::CONFIG_BOARD);

    zephyr::time::sleep(zephyr::time::Duration::secs_at_least(1));
    set_prompt(CStr::from_bytes_with_nul(b"\x1b[32mqemu\x1b[0m:~$ \0").unwrap());
}
