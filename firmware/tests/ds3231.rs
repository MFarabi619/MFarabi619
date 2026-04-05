#![no_std]
#![no_main]

use defmt::info;
use ds323x::{DateTimeAccess, Datelike, Ds323x, Timelike};
use esp_hal::{
    i2c::master::{Config as I2cConfig, I2c},
    time::Rate,
    timer::timg::TimerGroup,
};

const RTC_I2C_ADDRESS: u8 = 0x68;
const RTC_I2C_SDA_PIN: u32 = 15;
const RTC_I2C_SCL_PIN: u32 = 16;
const I2C_BUS_FREQUENCY_KHZ: u32 = 100;

struct Context {
    i2c_bus: I2c<'static, esp_hal::Blocking>,
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

        let i2c_bus = I2c::new(
            peripherals.I2C0,
            I2cConfig::default().with_frequency(Rate::from_khz(I2C_BUS_FREQUENCY_KHZ)),
        )
        .unwrap()
        .with_sda(peripherals.GPIO15)
        .with_scl(peripherals.GPIO16);

        info!(
            "DS3231 test initialized on I2C0 (SDA=GPIO{}, SCL=GPIO{}, addr={:#04x})",
            RTC_I2C_SDA_PIN,
            RTC_I2C_SCL_PIN,
            RTC_I2C_ADDRESS
        );

        Context { i2c_bus }
    }

    #[test]
    async fn ds3231_datetime_is_readable_on_i2c0_address_0x68(ctx: Context) {
        let mut i2c_bus = ctx.i2c_bus;

        i2c_bus
            .write(RTC_I2C_ADDRESS, &[])
            .expect("DS3231 did not ACK at address 0x68");

        let mut rtc_device = Ds323x::new_ds3231(i2c_bus);
        let datetime = rtc_device
            .datetime()
            .expect("failed to read datetime from DS3231");

        info!(
            "rtc datetime: {:04}-{:02}-{:02} {:02}:{:02}:{:02}",
            datetime.year(),
            datetime.month(),
            datetime.day(),
            datetime.hour(),
            datetime.minute(),
            datetime.second()
        );

        defmt::assert!(datetime.month() >= 1 && datetime.month() <= 12);
        defmt::assert!(datetime.day() >= 1 && datetime.day() <= 31);
        defmt::assert!(datetime.hour() <= 23);
        defmt::assert!(datetime.minute() <= 59);
        defmt::assert!(datetime.second() <= 59);
    }
}
