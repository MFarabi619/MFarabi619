use log_04::info;
use static_cell::StaticCell;
use zephyr::{embassy::Executor, raw::*};

unsafe extern "C" {
    fn wifi_pre_start();
    fn sdcard_mount_filesystem() -> core::ffi::c_int;
    fn schedule_deep_sleep();
    fn prompt_init(shell: *const core::ffi::c_void) -> bool;
    fn prompt_print_motd(shell: *const core::ffi::c_void, ip: *const u8);
    // fn get_ppp_iface() -> *mut net_if;
}

static EXECUTOR: StaticCell<Executor> = StaticCell::new();

#[unsafe(no_mangle)]
extern "C" fn rust_main() {
    unsafe {
        wifi_pre_start();
    }

    unsafe {
        zephyr::set_logger().unwrap();
    }
    info!("Microvisor starting");

    unsafe {
        sdcard_mount_filesystem();
        // schedule_deep_sleep();
    }

    crate::led::init();
    crate::wifi::init();

    unsafe {
        let ret = http_server_start();
        if ret == 0 {
            info!("HTTP server started");
        } else {
            info!("HTTP server start failed: {}", ret);
        }

        // let ppp_iface = get_ppp_iface();
        // if !ppp_iface.is_null() {
        //     let ret = net_if_up(ppp_iface);
        //     if ret == 0 {
        //         info!("PPP interface brought up");
        //     }
        // }
    }

    // unsafe {
    //     let sh = zephyr::raw::zr_shell_backend_uart_get_ptr() as *const core::ffi::c_void;
    //     prompt_init(sh);
    //     prompt_print_motd(sh, core::ptr::null());
    // }

    let executor = EXECUTOR.init(Executor::new());
    executor.run(|spawner: embassy_executor::Spawner| {
        spawner.spawn(crate::wifi::task().unwrap());
    })
}
