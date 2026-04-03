#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_time::{Duration, Ticker, Timer};
use esp_hal::{
    clock::CpuClock,
    gpio::{Level, Output, OutputConfig},
    i2c::master::{Config as I2cConfig, I2c},
    time::Rate,
    timer::timg::TimerGroup,
};
use panic_rtt_target as _;

extern crate alloc;

const I2C_BUS_FREQUENCY_KHZ: u32 = 100;

esp_bootloader_esp_idf::esp_app_desc!();

#[esp_rtos::main]
async fn main(_spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let hal_configuration = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(hal_configuration);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 73744);
    esp_alloc::heap_allocator!(size: 64 * 1024);

    let timer_group0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timer_group0.timer0);

    let _sensor_power_relay = Output::new(peripherals.GPIO5, Level::High, OutputConfig::default());
    Timer::after(Duration::from_millis(1_000)).await;

    let mut i2c_bus = I2c::new(
        peripherals.I2C0,
        I2cConfig::default().with_frequency(Rate::from_khz(I2C_BUS_FREQUENCY_KHZ)),
    )
    .unwrap()
    .with_sda(peripherals.GPIO15)
    .with_scl(peripherals.GPIO16)
    .into_async();

    info!(
        "i2c scan started on I2C0 (SDA=GPIO{}, SCL=GPIO{}, {}kHz)",
        15, 16, I2C_BUS_FREQUENCY_KHZ
    );

    let mut scan_interval = Ticker::every(Duration::from_secs(2));

    loop {
        scan_interval.next().await;
        info!("scanning I2C addresses 0x03..=0x77");

        let mut found_device_count: usize = 0;

        for i2c_address in 0x03_u8..=0x77_u8 {
            if i2c_bus.write_async(i2c_address, &[]).await.is_ok() {
                found_device_count += 1;
                info!("found i2c device at address {}", i2c_address);

                if i2c_address == 0x70 {
                    info!("address 0x70 often indicates a TCA9548A I2C multiplexer");
                }

                if (0x44_u8..=0x47_u8).contains(&i2c_address) {
                    info!("address {} matches a possible CHT832X sensor", i2c_address);
                }
            }
        }

        info!("i2c scan complete: {} device(s) found", found_device_count);
    }
}
