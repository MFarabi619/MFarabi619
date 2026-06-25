use oh_my_zephyr as shell;

#[cfg(all(CONFIG_HTTP_SERVER, not(CONFIG_ZTEST)))]
use crate::services::http;

#[cfg(not(CONFIG_ZTEST))]
use log::{info, warn};

#[cfg(all(CONFIG_NETWORKING, dt = "labels::modem"))]
use crate::networking::{cellular, dns, wifi};

#[cfg(all(CONFIG_NETWORKING, not(dt = "labels::modem")))]
use crate::networking::wifi;

#[cfg(all(CONFIG_NETWORKING, not(dt = "labels::modem"), CONFIG_WIREGUARD))]
use crate::networking::wireguard;

#[cfg(not(CONFIG_ZTEST))]
macro_rules! try_init {
    ($name:literal => $expr:expr) => {
        if let Err(e) = $expr {
            warn!("{}: {e}", $name);
        }
    };
}

#[cfg(CONFIG_BOOTLOADER_MCUBOOT)]
use zephyr::{
    error::to_result_void,
    raw::{boot_is_img_confirmed, boot_write_img_confirmed},
};

#[cfg(CONFIG_FS_FATFS_HAS_RTC)]
#[no_mangle]
extern "C" fn get_fattime() -> u32 {
    let mut wall_clock = shell::Timespec::default();
    if unsafe { shell::sys_clock_gettime(1, &mut wall_clock) } != 0
        || wall_clock.tv_sec < 1_577_836_800
    {
        return 0;
    }
    wall_clock.tv_sec += (zephyr::kconfig::CONFIG_PROMPT_TZ_OFFSET_MINUTES as i64) * 60;
    let mut calendar = shell::Tm::default();
    unsafe { shell::gmtime_r(&wall_clock.tv_sec, &mut calendar) };
    ((calendar.tm_year - 80) as u32) << 25
        | ((calendar.tm_mon + 1) as u32) << 21
        | (calendar.tm_mday as u32) << 16
        | (calendar.tm_hour as u32) << 11
        | (calendar.tm_min as u32) << 5
        | ((calendar.tm_sec / 2) as u32)
}

#[cfg(CONFIG_ZTEST)]
#[no_mangle]
extern "C" fn rust_main() {
    extern "C" {
        fn test_main();
    }
    unsafe { test_main() };
}

#[cfg(not(CONFIG_ZTEST))]
#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }
    info!("rust_main on {}", zephyr::kconfig::CONFIG_BOARD);

    #[cfg(all(CONFIG_NETWORKING, dt = "labels::modem"))]
    {
        try_init!("cellular" => cellular::initialize());
        try_init!("nat"      => cellular::nat::initialize());
        try_init!("dns"      => dns::initialize());
        try_init!("wifi ap"  => wifi::ap::initialize());
    }

    #[cfg(all(CONFIG_NETWORKING, not(dt = "labels::modem")))]
    if let Err(e) = wifi::sta::initialize() {
        warn!("wifi sta: {e}");
    } else {
        #[cfg(CONFIG_WIREGUARD)]
        try_init!("wireguard"   => wireguard::initialize());
        #[cfg(CONFIG_HTTP_SERVER)]
        try_init!("http server" => http::server::initialize());
    }

    #[cfg(CONFIG_BOOTLOADER_MCUBOOT)]
    if !unsafe { boot_is_img_confirmed() } {
        match to_result_void(unsafe { boot_write_img_confirmed() }) {
            Ok(()) => info!("boot: image confirmed"),
            Err(e) => warn!("boot confirm: {e}"),
        }
    }

    try_init!("shell" => shell::initialize());

    spawn_embassy_executor();

    #[cfg(CONFIG_DISPLAY)]
    spawn_ui_thread();
}

#[cfg(all(CONFIG_DISPLAY, not(CONFIG_ZTEST)))]
fn spawn_ui_thread() {
    let stack = UI_STACK.init_once(()).unwrap();
    let mut thread = UI_THREAD.init_once(stack).unwrap();
    thread.set_priority(7);
    thread.spawn(|| crate::programs::tui::display_loop());
}

#[cfg(not(CONFIG_ZTEST))]
static EXECUTOR: static_cell::StaticCell<zephyr::embassy::Executor> =
    static_cell::StaticCell::new();

#[cfg(not(CONFIG_ZTEST))]
fn spawn_embassy_executor() {
    let stack = EMBASSY_STACK.init_once(()).unwrap();
    let mut thread = EMBASSY_THREAD.init_once(stack).unwrap();
    thread.set_priority(5);
    thread.spawn(move || {
        let executor = EXECUTOR.init(zephyr::embassy::Executor::new());
        executor.run(|spawner| {
            let _ = spawner;
            #[cfg(all(CONFIG_NETWORKING, dt = "labels::modem"))]
            spawner.spawn(cellular::registration_watchdog()).unwrap();
        });
    });
}

#[cfg(not(CONFIG_ZTEST))]
zephyr::kobj_define! {
    static EMBASSY_THREAD: StaticThread;
    static EMBASSY_STACK: ThreadStack<2048>;
}

#[cfg(all(CONFIG_DISPLAY, not(CONFIG_ZTEST)))]
zephyr::kobj_define! {
    static UI_THREAD: StaticThread;
    static UI_STACK: ThreadStack<8192>;
}
