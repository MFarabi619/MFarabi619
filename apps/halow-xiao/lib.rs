#![no_std]

use zephyr::printk;

#[no_mangle]
extern "C" fn rust_main() {
    printk!("=== halow_xiao rust_main on {} ===\n", zephyr::kconfig::CONFIG_BOARD);
}
