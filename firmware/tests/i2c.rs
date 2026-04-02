//! I2C scanner integration test using embedded-test
//!
//! Scans both I2C0 (SDA=GPIO15, SCL=GPIO16) and I2C1 (SDA=GPIO17, SCL=GPIO18)
//! buses for devices at addresses 0x03..=0x77.

#![no_std]
#![no_main]

use defmt::info;
use esp_hal::{
    gpio::{Level, Output, OutputConfig},
    i2c::master::{Config as I2cConfig, I2c},
    time::Rate,
    timer::timg::TimerGroup,
};

const I2C0_SDA_PIN: u32 = 15;
const I2C0_SCL_PIN: u32 = 16;
const I2C1_SDA_PIN: u32 = 17;
const I2C1_SCL_PIN: u32 = 18;
const I2C_BUS_FREQUENCY_KHZ: u32 = 100;
const I2C_SCAN_ADDRESS_MIN: u8 = 0x03;
const I2C_SCAN_ADDRESS_MAX: u8 = 0x77;

struct Context {
    i2c0: I2c<'static, esp_hal::Blocking>,
    i2c1: I2c<'static, esp_hal::Blocking>,
}

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::tests(executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Context {
        let peripherals = esp_hal::init(esp_hal::Config::default());

        let timer_group0 = TimerGroup::new(peripherals.TIMG0);
        esp_rtos::start(timer_group0.timer0);

        rtt_target::rtt_init_defmt!();

        let _sensor_power_relay =
            Output::new(peripherals.GPIO5, Level::High, OutputConfig::default());

        let delay = esp_hal::delay::Delay::new();
        delay.delay_millis(1_000);

        let i2c0 = I2c::new(
            peripherals.I2C0,
            I2cConfig::default().with_frequency(Rate::from_khz(I2C_BUS_FREQUENCY_KHZ)),
        )
        .unwrap()
        .with_sda(peripherals.GPIO15)
        .with_scl(peripherals.GPIO16);

        let i2c1 = I2c::new(
            peripherals.I2C1,
            I2cConfig::default().with_frequency(Rate::from_khz(I2C_BUS_FREQUENCY_KHZ)),
        )
        .unwrap()
        .with_sda(peripherals.GPIO17)
        .with_scl(peripherals.GPIO18);

        info!("I2C scanner test initialized");

        Context { i2c0, i2c1 }
    }

    async fn scan_bus(
        channel_name: &str,
        sda_pin: u32,
        scl_pin: u32,
        i2c: I2c<'_, esp_hal::Blocking>,
    ) -> usize {
        let mut i2c_async = i2c.into_async();

        info!(
            "scanning {} (SDA=GPIO{}, SCL=GPIO{}) addresses {:#04x}..={:#04x}",
            channel_name,
            sda_pin,
            scl_pin,
            I2C_SCAN_ADDRESS_MIN,
            I2C_SCAN_ADDRESS_MAX
        );

        let mut found_count: usize = 0;

        for address in I2C_SCAN_ADDRESS_MIN..=I2C_SCAN_ADDRESS_MAX {
            if i2c_async.write_async(address, &[]).await.is_ok() {
                found_count += 1;
                info!("found device at {:#04x}", address);
            }
        }

        info!("{} scan complete: {} device(s)", channel_name, found_count);
        found_count
    }

    #[test]
    async fn scan_i2c_buses(ctx: Context) {
        let i2c0 = ctx.i2c0;
        let i2c1 = ctx.i2c1;

        let i2c0_count = scan_bus("I2C0", I2C0_SDA_PIN, I2C0_SCL_PIN, i2c0).await;
        let i2c1_count = scan_bus("I2C1", I2C1_SDA_PIN, I2C1_SCL_PIN, i2c1).await;

        info!(
            "total: I2C0={}, I2C1={}, combined={}",
            i2c0_count,
            i2c1_count,
            i2c0_count + i2c1_count
        );
    }
}
