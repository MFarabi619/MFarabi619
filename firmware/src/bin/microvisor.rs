#![no_std]
#![no_main]
#![feature(impl_trait_in_assoc_type)]
#![deny(
    clippy::mem_forget,
    reason = "mem::forget is generally not safe to do with esp_hal types, especially those \
    holding buffers for the duration of a data transfer."
)]
#![deny(clippy::large_stack_frames)]

extern crate alloc;

use defmt::info;
use embassy_executor::Spawner;
use embassy_time::{Duration, Instant, Timer};
use esp_hal::{
    clock::CpuClock,
    delay::Delay,
    gpio::{Level, Output, OutputConfig},
    interrupt::software::SoftwareInterruptControl,
    timer::timg::TimerGroup,
};
use esp_storage::FlashStorage;
use heapless::String as HeaplessString;
use panic_rtt_target as _;

use firmware::{
    boot,
    config::{self, runtime::WifiCredentials},
    state::{self, AppState},
};

esp_bootloader_esp_idf::esp_app_desc!();

#[allow(
    clippy::large_stack_frames,
    reason = "it's not unusual to allocate larger buffers etc. in main"
)]
#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 73744);
    esp_alloc::heap_allocator!(size: 64 * 1024);
    esp_alloc::psram_allocator!(peripherals.PSRAM, esp_hal::psram);

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    let sw_ints = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
    esp_rtos::start(timg0.timer0, sw_ints.software_interrupt0);

    info!("Embassy initialized!");
    info!("host_platform={}", config::PLATFORM);
    info!("active_user_key={}", config::ACTIVE_USER_KEY);
    info!("time_zone={}", config::time::ZONE);
    info!(
        "filesystem.sd_card: device={} fs_type={} data_log_path={}",
        config::sd_card::DEVICE,
        config::sd_card::FS_TYPE,
        config::sd_card::DATA_LOG_PATH
    );
    info!(
        "networking.ap_fallback={} ap_ssid={} ap_channel={} ap_max_connections={} ap_auth_mode={}",
        config::wifi::FALLBACK_TO_AP,
        config::wifi::ap::SSID,
        config::wifi::ap::CHANNEL,
        config::wifi::ap::MAX_CONNECTIONS,
        config::wifi::ap::AUTH_MODE,
    );

    boot::validate_ota_slot();

    let _sensor_power_relay = match config::i2c::LEGACY_POWER_GPIO {
        5 => Output::new(peripherals.GPIO5, Level::High, OutputConfig::default()),
        unsupported_gpio => {
            panic!("unsupported sensor_power_enable_gpio={}", unsupported_gpio)
        }
    };
    Delay::new().delay_millis(1_000);

    let sd_size_mb = boot::initialize_sd_and_filesystem(
        peripherals.SPI2,
        peripherals.GPIO10,
        peripherals.GPIO11,
        peripherals.GPIO12,
        peripherals.GPIO13,
    );

    let (mut i2c0_bus, mut i2c1_bus) = boot::initialize_i2c_buses(
        peripherals.I2C0,
        peripherals.I2C1,
        peripherals.GPIO8,
        peripherals.GPIO9,
        peripherals.GPIO17,
        peripherals.GPIO18,
    );

    state::set_app_state(AppState {
        cloud_event_source: config::cloudevents::SOURCE,
        cloud_event_type: config::cloudevents::EVENT_TYPE,
        boot_timestamp_seconds: Instant::now().as_secs(),
    });

    let mut flash = FlashStorage::new();
    let credentials = config::runtime::read_credentials(&mut flash).unwrap_or_else(|| {
        info!("no credentials in flash, using defaults");
        WifiCredentials {
            ssid: HeaplessString::try_from(config::runtime::DEFAULT_SSID).unwrap(),
            password: HeaplessString::try_from(config::runtime::DEFAULT_PASSWORD).unwrap(),
        }
    });

    let network = boot::connect_networking(
        spawner,
        peripherals.WIFI,
        peripherals.BT,
        &credentials,
    )
    .await;

    boot::spawn_sensor_tasks(&spawner, &mut i2c0_bus, &mut i2c1_bus);

    boot::wait_for_dhcp(network.stack, sd_size_mb).await;

    boot::start_services(&spawner, network.stack);

    let _ble_controller = network.ble_controller;
    loop {
        Timer::after(Duration::from_secs(60)).await;
    }
}
