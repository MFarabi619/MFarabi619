#![no_std]

use log::info;

extern "C" {
    fn wifiSTAConnectStored() -> i32;
}

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }

    info!("rust_main on {}", zephyr::kconfig::CONFIG_BOARD);

    let ret = unsafe { wifiSTAConnectStored() };
    info!("wifi connect_stored = {}", ret);
}
