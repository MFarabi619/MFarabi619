// Anchor the zephyr crate so its #[panic_handler] and #[global_allocator]
// get linked into the staticlib. (Xtensa anchors zephyr via its rich rust_main.)
extern crate zephyr;

#[no_mangle]
extern "C" fn rust_main() {
    #[cfg(CONFIG_ZTEST)]
    {
        extern "C" {
            fn test_main();
        }
        unsafe { test_main() };
        return;
    }

    #[cfg(not(CONFIG_ZTEST))]
    {
        unsafe {
            zephyr::set_logger().unwrap();
        }
        log::info!("rust_main on {}", zephyr::kconfig::CONFIG_BOARD);

        #[cfg(CONFIG_OH_MY_ZEPHYR)]
        if let Err(e) = oh_my_zephyr::initialize() {
            log::warn!("shell: {e}");
        }
    }
}
