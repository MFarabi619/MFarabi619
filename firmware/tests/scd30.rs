// https://sensirion.com/products/catalog/SCD30
#![no_std]
#![no_main]

use defmt::info;
use embassy_time::{Duration, Timer};
use esp_hal::{
    gpio::{Level, Output, OutputConfig},
    i2c::master::{Config as I2cConfig, I2c},
    time::Rate,
    timer::timg::TimerGroup,
};
use scd30_interface::{
    asynch::Scd30,
    data::{
        AmbientPressureCompensation, AutomaticSelfCalibration, DataStatus, MeasurementInterval,
    },
};

const SCD30_I2C_ADDRESS: u8 = 0x61;
const I2C0_SDA_PIN: u32 = 15;
const I2C0_SCL_PIN: u32 = 16;
const I2C1_SDA_PIN: u32 = 17;
const I2C1_SCL_PIN: u32 = 18;
const SENSOR_POWER_ENABLE_PIN: u32 = 5;
const SCD30_I2C_FREQUENCY_KHZ: u32 = 100;

const DATA_READY_POLL_RETRIES: usize = 40;
const DATA_READY_POLL_INTERVAL_MS: u64 = 250;

struct Context {
    i2c0: I2c<'static, esp_hal::Blocking>,
    i2c1: I2c<'static, esp_hal::Blocking>,
}

fn select_scd30_bus(context: Context) -> I2c<'static, esp_hal::Blocking> {
    let Context { i2c0, i2c1 } = context;
    let mut i2c0_bus = i2c0;
    let mut i2c1_bus = i2c1;

    if i2c1_bus.write(SCD30_I2C_ADDRESS, &[]).is_ok() {
        info!(
            "SCD30 detected on I2C1 (SDA=GPIO{}, SCL=GPIO{})",
            I2C1_SDA_PIN, I2C1_SCL_PIN
        );
        i2c1_bus
    } else if i2c0_bus.write(SCD30_I2C_ADDRESS, &[]).is_ok() {
        info!(
            "SCD30 detected on I2C0 (SDA=GPIO{}, SCL=GPIO{})",
            I2C0_SDA_PIN, I2C0_SCL_PIN
        );
        i2c0_bus
    } else {
        panic!("SCD30 did not ACK on I2C0 or I2C1 at address 0x61");
    }
}

fn assert_measurement_is_sane(co2_ppm: f32, temperature_celsius: f32, humidity_percent: f32) {
    defmt::assert!(co2_ppm.is_finite());
    defmt::assert!(temperature_celsius.is_finite());
    defmt::assert!(humidity_percent.is_finite());

    defmt::assert!(co2_ppm >= 0.0);
    defmt::assert!(co2_ppm <= 40_000.0);
    defmt::assert!(temperature_celsius >= -40.0);
    defmt::assert!(temperature_celsius <= 125.0);
    defmt::assert!(humidity_percent >= 0.0);
    defmt::assert!(humidity_percent <= 100.5);
}

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::tests(default_timeout = 120, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Context {
        let peripherals = esp_hal::init(esp_hal::Config::default());

        let timer_group0 = TimerGroup::new(peripherals.TIMG0);
        esp_rtos::start(timer_group0.timer0);

        rtt_target::rtt_init_defmt!();

        let sensor_power_enable =
            Output::new(peripherals.GPIO5, Level::High, OutputConfig::default());
        core::mem::forget(sensor_power_enable);

        let delay = esp_hal::delay::Delay::new();
        delay.delay_millis(1_500);

        let i2c0 = I2c::new(
            peripherals.I2C0,
            I2cConfig::default().with_frequency(Rate::from_khz(SCD30_I2C_FREQUENCY_KHZ)),
        )
        .unwrap()
        .with_sda(peripherals.GPIO15)
        .with_scl(peripherals.GPIO16);

        let i2c1 = I2c::new(
            peripherals.I2C1,
            I2cConfig::default().with_frequency(Rate::from_khz(SCD30_I2C_FREQUENCY_KHZ)),
        )
        .unwrap()
        .with_sda(peripherals.GPIO17)
        .with_scl(peripherals.GPIO18);

        info!(
            "SCD30 test initialized (I2C0 SDA=GPIO{} SCL=GPIO{}, I2C1 SDA=GPIO{} SCL=GPIO{}, power=GPIO{})",
            I2C0_SDA_PIN,
            I2C0_SCL_PIN,
            I2C1_SDA_PIN,
            I2C1_SCL_PIN,
            SENSOR_POWER_ENABLE_PIN
        );

        Context { i2c0, i2c1 }
    }

    #[test]
    #[timeout(120)]
    async fn scd30_async_smoke_test(ctx: Context) {
        let selected_i2c_bus = select_scd30_bus(ctx);
        let i2c_bus_async = selected_i2c_bus.into_async();
        let mut scd30_sensor = Scd30::new(i2c_bus_async);

        let firmware_version = scd30_sensor
            .read_firmware_version()
            .await
            .expect("failed to read SCD30 firmware version");
        info!(
            "firmware version: {}.{}",
            firmware_version.major,
            firmware_version.minor
        );
        defmt::assert!(firmware_version.major > 0);

        let _ = scd30_sensor.stop_continuous_measurements().await;
        Timer::after(Duration::from_millis(100)).await;

        scd30_sensor
            .set_measurement_interval(MeasurementInterval::try_from(2).unwrap())
            .await
            .expect("failed to set SCD30 measurement interval");

        scd30_sensor
            .set_automatic_self_calibration(AutomaticSelfCalibration::Active)
            .await
            .expect("failed to set SCD30 ASC state");

        let asc_state = scd30_sensor
            .get_automatic_self_calibration()
            .await
            .expect("failed to get SCD30 ASC state");
        defmt::assert_eq!(asc_state, AutomaticSelfCalibration::Active);

        scd30_sensor
            .trigger_continuous_measurements(Some(AmbientPressureCompensation::DefaultPressure))
            .await
            .expect("failed to start SCD30 continuous measurement");

        let mut measurement_ready = false;
        for _attempt_index in 0..DATA_READY_POLL_RETRIES {
            let data_status = scd30_sensor
                .is_data_ready()
                .await
                .expect("failed to read SCD30 data status");

            if data_status == DataStatus::Ready {
                measurement_ready = true;
                break;
            }

            Timer::after(Duration::from_millis(DATA_READY_POLL_INTERVAL_MS)).await;
        }
        defmt::assert!(measurement_ready);

        let measurement = scd30_sensor
            .read_measurement()
            .await
            .expect("failed to read SCD30 measurement");

        assert_measurement_is_sane(
            measurement.co2_concentration,
            measurement.temperature,
            measurement.humidity,
        );

        info!(
            "measurement: co2={=f32}ppm temp={=f32}C rh={=f32}%",
            measurement.co2_concentration,
            measurement.temperature,
            measurement.humidity
        );

        scd30_sensor
            .stop_continuous_measurements()
            .await
            .expect("failed to stop SCD30 continuous measurement");
    }
}
