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
use embassy_time::{Duration, Timer};
use esp_hal::{
    clock::CpuClock,
    delay::Delay,
    gpio::{Level, Output, OutputConfig},
    interrupt::software::SoftwareInterruptControl,
    timer::timg::TimerGroup,
};
use esp_storage::FlashStorage;
use panic_rtt_target as _;

use firmware::{
    boot,
    config::{app, board},
    networking::wifi,
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
    info!("host_platform={}", board::PLATFORM);
    info!("active_user_key={}", app::ACTIVE_USER_KEY);
    info!("time_zone={}", app::time::ZONE);
    info!(
        "filesystem.sd_card: device={} fs_type={} data_log_path={}",
        app::sd_card::DEVICE,
        app::sd_card::FS_TYPE,
        app::sd_card::DATA_LOG_PATH
    );
    info!(
        "networking.ap_fallback={} ap_ssid={} ap_channel={} ap_max_connections={} ap_auth_mode={}",
        app::wifi::FALLBACK_TO_AP,
        app::wifi::ap::SSID,
        app::wifi::ap::CHANNEL,
        app::wifi::ap::MAX_CONNECTIONS,
        app::wifi::ap::AUTH_MODE,
    );

    boot::validate_ota_slot();

    let _sensor_power_relay = match board::i2c::LEGACY_POWER_GPIO {
        5 => Output::new(peripherals.GPIO5, Level::High, OutputConfig::default()),
        unsupported_gpio => {
            panic!("unsupported sensor_power_enable_gpio={}", unsupported_gpio)
        }
    };
    Delay::new().delay_millis(1_000);

    boot::initialize_sd_and_filesystem(
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
    boot::discover_i2c_devices(&mut i2c0_bus, &mut i2c1_bus).await;

    let mut flash = FlashStorage::new();
    let credentials = wifi::load_credentials_or_default(&mut flash);

    let network = boot::initialize_networking(
        spawner,
        peripherals.WIFI,
        peripherals.BT,
        &credentials,
    )
    .await;

    boot::spawn_sensor_tasks(&spawner, &mut i2c0_bus, &mut i2c1_bus);
    boot::start_services(&spawner, network.stack);

    let _ble_controller = network.ble_controller;
    loop {
        Timer::after(Duration::from_secs(60)).await;
    }
}
