use core::ffi::{c_int, c_void};

#[repr(C)]
struct InitEntry {
    init_fn: Option<unsafe extern "C" fn() -> c_int>,
    dev: *const c_void,
}

unsafe impl Sync for InitEntry {}

unsafe extern "C" {
    fn esp_flash_app_init();
    fn esp_flash_init_default_chip() -> c_int;
}

unsafe extern "C" fn flash_default_chip_init() -> c_int {
    unsafe {
        esp_flash_app_init();
        esp_flash_init_default_chip();
    }
    0
}

#[used]
#[link_section = ".z_init_POST_KERNEL_P_99_SUB_0_"]
static FLASH_INIT_ENTRY: InitEntry = InitEntry {
    init_fn: Some(flash_default_chip_init),
    dev: core::ptr::null(),
};
