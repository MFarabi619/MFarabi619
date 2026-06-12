use core::ffi::c_int;
use zephyr::raw::init_entry;

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

#[repr(transparent)]
struct InitEntry(#[allow(dead_code)] init_entry);
unsafe impl Sync for InitEntry {}

#[used]
#[link_section = ".z_init_POST_KERNEL_P_99_SUB_0_"]
static FLASH_INIT_ENTRY: InitEntry = InitEntry(init_entry {
    init_fn: Some(flash_default_chip_init),
    dev: core::ptr::null(),
});
