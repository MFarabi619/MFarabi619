use embassy_time::{Duration, Timer};
use log_04::info;
use static_cell::StaticCell;
use zephyr::{embassy::Executor, raw::*};

unsafe extern "C" {
    fn wifi_pre_start();
    fn sdcard_mount_filesystem() -> core::ffi::c_int;
    fn schedule_deep_sleep();
    fn prompt_init(shell: *const core::ffi::c_void) -> bool;
    fn prompt_print_motd(shell: *const core::ffi::c_void, ip: *const u8);
    // fn boot_websocket_shell();
    // fn get_ppp_iface() -> *mut net_if;
}

const MQTT_RECONNECT_DELAY_SECONDS: u64 = 10;
const MQTT_WIFI_WAIT_SECONDS: u64 = 5;

#[embassy_executor::task]
async fn mqtt_task() {
    Timer::after(Duration::from_secs(MQTT_WIFI_WAIT_SECONDS)).await;

    if let Err(error) = crate::mqtt::init() {
        info!("MQTT init failed: {}", error);
        return;
    }

    if !crate::mqtt::is_configured() {
        info!("MQTT broker not configured, skipping MQTT task");
        return;
    }

    loop {
        while !crate::wifi::is_connected() {
            Timer::after(Duration::from_secs(MQTT_WIFI_WAIT_SECONDS)).await;
        }

        if crate::mqtt::connect().is_err() {
            Timer::after(Duration::from_secs(MQTT_RECONNECT_DELAY_SECONDS)).await;
            continue;
        }

        for _ in 0..50 {
            let _ = crate::mqtt::poll(100);
            if crate::mqtt::is_connected() {
                break;
            }
            Timer::after(Duration::from_millis(100)).await;
        }

        if !crate::mqtt::is_connected() {
            info!("MQTT connection timed out");
            let _ = crate::mqtt::disconnect();
            Timer::after(Duration::from_secs(MQTT_RECONNECT_DELAY_SECONDS)).await;
            continue;
        }

        crate::home_assistant::publish_discovery_configs();
        crate::publish::publish_config_state();

        while crate::mqtt::is_connected() {
            crate::publish::publish_all();

            if crate::mqtt::deep_sleep_enabled() {
                let _ = crate::mqtt::disconnect();
                unsafe { schedule_deep_sleep() };
                Timer::after(Duration::from_secs(MQTT_RECONNECT_DELAY_SECONDS)).await;
                break;
            }

            let interval = crate::mqtt::publish_interval() as u64;
            let deadline = embassy_time::Instant::now() + Duration::from_secs(interval);
            while embassy_time::Instant::now() < deadline && crate::mqtt::is_connected() {
                let keepalive_ms = crate::mqtt::keepalive_time_left();
                let poll_timeout = keepalive_ms.min(500);
                let _ = crate::mqtt::poll(poll_timeout);

                if let Some((topic, payload)) = crate::mqtt::get_incoming_command() {
                    crate::commands::handle_command(topic, payload);
                }

                Timer::after(Duration::from_millis(100)).await;
            }
        }

        info!("MQTT connection lost, reconnecting");
        Timer::after(Duration::from_secs(MQTT_RECONNECT_DELAY_SECONDS)).await;
    }
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
        // boot_websocket_shell();

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
        spawner.spawn(mqtt_task().unwrap());
    })
}
