#![no_std]

use zephyr::printk;

extern "C" {
    fn wifiSTAConnectStored() -> i32;
}

#[no_mangle]
extern "C" fn rust_main() {
    printk!("=== rust_main on {} ===\n", zephyr::kconfig::CONFIG_BOARD);

    let ret = unsafe { wifiSTAConnectStored() };
    printk!("[wifi] connect_stored = {}\n", ret);
}
