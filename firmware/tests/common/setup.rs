//! `Device` — the system under test, and the helpers that build it.

use defmt::info;
use embassy_net::{Ipv4Cidr, Runner, Stack, StackResources, StaticConfigV4};
use embassy_time::{Duration, Timer};
use esp_hal::{
    clock::CpuClock,
    i2c::master::{Config as I2cConfig, I2c},
    interrupt::software::SoftwareInterruptControl,
    rng::Rng,
    time::Rate,
    timer::timg::TimerGroup,
};
use esp_radio::wifi::{Interface, Interfaces, WifiController};
use static_cell::StaticCell;

use firmware::config::board;
use firmware::filesystems::sd;

/// The system under test.
///
/// Every screenplay test signature is `async fn user_does_x(mut device:
/// Device) -> Result<(), &'static str>`. Tasks operate on `&mut Device`
/// so call sites read as English without exposing peripheral types.
pub struct Device {
    pub wifi_controller: Option<WifiController<'static>>,
    pub wifi_interfaces: Option<Interfaces<'static>>,
    pub embassy_network_stack: Option<Stack<'static>>,
    pub embassy_network_seed: u64,
    pub i2c_bus_0: Option<I2c<'static, esp_hal::Blocking>>,
    pub i2c_bus_1: Option<I2c<'static, esp_hal::Blocking>>,
}

pub fn boot_device() -> Device {
    let hardware_config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(hardware_config);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 48 * 1024);
    esp_alloc::heap_allocator!(size: 48 * 1024);
    esp_alloc::psram_allocator!(peripherals.PSRAM, esp_hal::psram);

    let timer_group_zero = TimerGroup::new(peripherals.TIMG0);
    let software_interrupts = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
    esp_rtos::start(timer_group_zero.timer0, software_interrupts.software_interrupt0);

    info!("device boot: embassy + esp_rtos started");

    let sd_card_size_megabytes = sd::initialize(
        peripherals.SPI2,
        peripherals.GPIO10,
        peripherals.GPIO11,
        peripherals.GPIO12,
        peripherals.GPIO13,
    );
    info!(
        "device boot: SD card probe reported size_mib={=u32}",
        sd_card_size_megabytes
    );

    // I2C buses are wired from the canonical transport config in `config::i2c`.
    // If you re-wire the board, update config — NOT the tests — and every
    // screenplay test picks up the change automatically.
    let i2c_bus_0 = I2c::new(
        peripherals.I2C0,
        I2cConfig::default().with_frequency(Rate::from_khz(board::i2c::FREQUENCY_KHZ)),
    )
    .expect("device: failed to create I2C0 driver")
    .with_sda(peripherals.GPIO8)
    .with_scl(peripherals.GPIO9);
    info!(
        "device boot: I2C0 wired sda=GPIO{=u8} scl=GPIO{=u8} freq_khz={=u32}",
        8u8, 9u8, board::i2c::FREQUENCY_KHZ
    );

    let i2c_bus_1 = I2c::new(
        peripherals.I2C1,
        I2cConfig::default().with_frequency(Rate::from_khz(board::i2c::FREQUENCY_KHZ)),
    )
    .expect("device: failed to create I2C1 driver")
    .with_sda(peripherals.GPIO17)
    .with_scl(peripherals.GPIO18);
    info!(
        "device boot: I2C1 wired sda=GPIO{=u8} scl=GPIO{=u8} freq_khz={=u32}",
        17u8, 18u8, board::i2c::FREQUENCY_KHZ
    );

    let random_number_generator = Rng::new();
    let random_seed_high_word = u64::from(random_number_generator.random());
    let random_seed_low_word = u64::from(random_number_generator.random());
    let embassy_network_seed = (random_seed_high_word << 32) | random_seed_low_word;

    let (wifi_controller, wifi_interfaces) = esp_radio::wifi::new(
        peripherals.WIFI,
        esp_radio::wifi::ControllerConfig::default()
            .with_static_rx_buf_num(4)
            .with_dynamic_rx_buf_num(16)
            .with_dynamic_tx_buf_num(16),
    )
    .expect("device: failed to initialise WiFi controller");

    Device {
        wifi_controller: Some(wifi_controller),
        wifi_interfaces: Some(wifi_interfaces),
        embassy_network_stack: None,
        embassy_network_seed,
        i2c_bus_0: Some(i2c_bus_0),
        i2c_bus_1: Some(i2c_bus_1),
    }
}

pub fn build_access_point_stack(
    access_point_interface: Interface<'static>,
    embassy_network_seed: u64,
) -> (Stack<'static>, Runner<'static, Interface<'static>>) {
    let static_ipv4_config = embassy_net::Config::ipv4_static(StaticConfigV4 {
        address: Ipv4Cidr::new(core::net::Ipv4Addr::new(192, 168, 4, 1), 24),
        gateway: Some(core::net::Ipv4Addr::new(192, 168, 4, 1)),
        dns_servers: Default::default(),
    });

    static EMBASSY_STACK_RESOURCES: StaticCell<StackResources<3>> = StaticCell::new();
    let stack_resources = EMBASSY_STACK_RESOURCES.init(StackResources::<3>::new());

    embassy_net::new(
        access_point_interface,
        static_ipv4_config,
        stack_resources,
        embassy_network_seed,
    )
}

#[embassy_executor::task]
pub async fn run_embassy_network(
    mut network_runner: Runner<'static, Interface<'static>>,
) -> ! {
    network_runner.run().await
}

pub async fn delay_seconds(seconds: u64) {
    Timer::after(Duration::from_secs(seconds)).await;
}
