use core::sync::atomic::Ordering;
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
    fn mqtt_helper_get_epoch_seconds() -> i64;
}

fn capture_boot_epoch_once() {
    if crate::diagnostics::BOOT_EPOCH_SECONDS.load(Ordering::Relaxed) > 0 {
        return;
    }
    let epoch_now = unsafe { mqtt_helper_get_epoch_seconds() };
    if epoch_now <= 0 {
        return;
    }
    let uptime_seconds = unsafe { k_uptime_get() / 1000 };
    let boot_epoch = (epoch_now - uptime_seconds) as u32;
    crate::diagnostics::BOOT_EPOCH_SECONDS.store(boot_epoch, Ordering::Relaxed);
}

const MQTT_RECONNECT_DELAY_SECONDS: u64 = 10;
const MQTT_WIFI_WAIT_SECONDS: u64 = 5;

#[embassy_executor::task]
async fn mqtt_task() {
    Timer::after(Duration::from_secs(MQTT_WIFI_WAIT_SECONDS)).await;

    if let Err(error) = crate::mqtt::init() {
        info!("MQTT init failed: {:?}", error);
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

        if let Err(error) = crate::mqtt::connect() {
            info!("MQTT connect failed before TCP/CONNECT: {:?}", error);
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
            info!("MQTT no CONNACK in 5s - broker silent or rejecting handshake");
            let _ = crate::mqtt::disconnect();
            Timer::after(Duration::from_secs(MQTT_RECONNECT_DELAY_SECONDS)).await;
            continue;
        }

        crate::mqtt::note_connection_state(true);
        crate::home_assistant::publish_discovery_configs().await;
        crate::publish::publish_config_state();
        crate::publish::publish_firmware_info();
        crate::publish::publish_update_state();

        while crate::mqtt::is_connected() {
            capture_boot_epoch_once();
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
                crate::mqtt::note_connection_state(crate::mqtt::is_connected());

                if let Some((topic, payload)) = crate::mqtt::get_incoming_command() {
                    crate::commands::handle_command(topic, payload).await;
                }

                Timer::after(Duration::from_millis(100)).await;
            }
        }

        crate::mqtt::note_connection_state(false);
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

    let boot_count = crate::diagnostics::increment_boot_count();
    info!("Boot count: {}", boot_count);

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
    }

    let executor = EXECUTOR.init(Executor::new());
    executor.run(|spawner: embassy_executor::Spawner| {
        spawner.spawn(crate::wifi::task().unwrap());
        spawner.spawn(mqtt_task().unwrap());
    })
}
