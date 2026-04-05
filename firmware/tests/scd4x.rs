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
use scd4x::Scd4xAsync;

const I2C0_SDA_PIN: u32 = 15;
const I2C0_SCL_PIN: u32 = 16;
const I2C1_SDA_PIN: u32 = 17;
const I2C1_SCL_PIN: u32 = 18;
const SENSOR_POWER_ENABLE_PIN: u32 = 5;
const SCD4X_I2C_FREQUENCY_KHZ: u32 = 100;

const PERIODIC_READY_POLL_RETRIES: usize = 20;
const PERIODIC_READY_POLL_INTERVAL_MS: u64 = 500;
const LOW_POWER_READY_POLL_RETRIES: usize = 90;
const LOW_POWER_READY_POLL_INTERVAL_MS: u64 = 500;

struct Context {
    i2c0: I2c<'static, esp_hal::Blocking>,
    i2c1: I2c<'static, esp_hal::Blocking>,
}

fn assert_measurement_is_sane(co2_ppm: u16, temperature_celsius: f32, humidity_percent: f32) {
    defmt::assert!(co2_ppm > 0);
    defmt::assert!(co2_ppm <= 40_000);
    defmt::assert!(temperature_celsius >= -20.0);
    defmt::assert!(temperature_celsius <= 85.0);
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

        let sensor_power_enable = Output::new(
            peripherals.GPIO5,
            Level::High,
            OutputConfig::default(),
        );
        core::mem::forget(sensor_power_enable);

        let delay = esp_hal::delay::Delay::new();
        delay.delay_millis(1_500);

        let i2c0 = I2c::new(
            peripherals.I2C0,
            I2cConfig::default().with_frequency(Rate::from_khz(SCD4X_I2C_FREQUENCY_KHZ)),
        )
        .unwrap()
        .with_sda(peripherals.GPIO15)
        .with_scl(peripherals.GPIO16);

        let i2c1 = I2c::new(
            peripherals.I2C1,
            I2cConfig::default().with_frequency(Rate::from_khz(SCD4X_I2C_FREQUENCY_KHZ)),
        )
        .unwrap()
        .with_sda(peripherals.GPIO17)
        .with_scl(peripherals.GPIO18);

        info!(
            "SCD4x test initialized (I2C0 SDA=GPIO{} SCL=GPIO{}, I2C1 SDA=GPIO{} SCL=GPIO{}, power=GPIO{})",
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
    async fn scd4x_async_api_smoke_test(ctx: Context) {
        let Context { i2c0, i2c1 } = ctx;
        let mut i2c0_bus = i2c0;
        let mut i2c1_bus = i2c1;

        let selected_i2c_bus = if i2c1_bus.write(0x62, &[]).is_ok() {
            info!(
                "SCD4x detected on I2C1 (SDA=GPIO{}, SCL=GPIO{})",
                I2C1_SDA_PIN,
                I2C1_SCL_PIN
            );
            i2c1_bus
        } else if i2c0_bus.write(0x62, &[]).is_ok() {
            info!(
                "SCD4x detected on I2C0 (SDA=GPIO{}, SCL=GPIO{})",
                I2C0_SDA_PIN,
                I2C0_SCL_PIN
            );
            i2c0_bus
        } else {
            panic!("SCD4x did not ACK on I2C0 or I2C1 at address 0x62");
        };

        let i2c_bus_async = selected_i2c_bus.into_async();
        let mut scd4x_sensor = Scd4xAsync::new(i2c_bus_async, embassy_time::Delay);

        let _ = scd4x_sensor.stop_periodic_measurement().await;
        Timer::after(Duration::from_millis(500)).await;

        let mut reinit_succeeded = false;
        for _attempt_index in 0..3 {
            if scd4x_sensor.reinit().await.is_ok() {
                reinit_succeeded = true;
                break;
            }

            Timer::after(Duration::from_millis(100)).await;
        }
        defmt::assert!(reinit_succeeded);

        let serial_number_first = scd4x_sensor
            .serial_number()
            .await
            .expect("failed to read first SCD4x serial number");
        let serial_number_second = scd4x_sensor
            .serial_number()
            .await
            .expect("failed to read second SCD4x serial number");

        defmt::assert!(serial_number_first != 0);
        defmt::assert_eq!(serial_number_first, serial_number_second);

        let temperature_offset_celsius = scd4x_sensor
            .temperature_offset()
            .await
            .expect("failed to read SCD4x temperature offset");
        let sensor_altitude_meters = scd4x_sensor
            .altitude()
            .await
            .expect("failed to read SCD4x altitude");
        let automatic_self_calibration_enabled = scd4x_sensor
            .automatic_self_calibration()
            .await
            .expect("failed to read SCD4x ASC state");

        defmt::assert!(temperature_offset_celsius.is_finite());
        defmt::assert!(temperature_offset_celsius >= 0.0);
        defmt::assert!(temperature_offset_celsius <= 175.0);
        defmt::assert!(sensor_altitude_meters <= 3_000);

        info!(
            "serial={}, t_offset={=f32}C altitude={}m asc_enabled={}",
            serial_number_first,
            temperature_offset_celsius,
            sensor_altitude_meters,
            automatic_self_calibration_enabled
        );

        let self_test_is_ok = scd4x_sensor
            .self_test_is_ok()
            .await
            .expect("failed to run SCD4x self-test");
        defmt::assert!(self_test_is_ok);

        scd4x_sensor
            .start_periodic_measurement()
            .await
            .expect("failed to start periodic SCD4x measurement");

        scd4x_sensor
            .set_ambient_pressure(1_013)
            .await
            .expect("failed to set ambient pressure during periodic measurement");

        let mut periodic_data_ready = false;
        for _attempt_index in 0..PERIODIC_READY_POLL_RETRIES {
            if scd4x_sensor
                .data_ready_status()
                .await
                .expect("failed to read periodic SCD4x data_ready_status")
            {
                periodic_data_ready = true;
                break;
            }

            Timer::after(Duration::from_millis(PERIODIC_READY_POLL_INTERVAL_MS)).await;
        }

        defmt::assert!(periodic_data_ready);

        let periodic_measurement = scd4x_sensor
            .measurement()
            .await
            .expect("failed to read periodic SCD4x measurement");

        assert_measurement_is_sane(
            periodic_measurement.co2,
            periodic_measurement.temperature,
            periodic_measurement.humidity,
        );

        info!(
            "periodic: co2={}ppm temp={=f32}C rh={=f32}%",
            periodic_measurement.co2,
            periodic_measurement.temperature,
            periodic_measurement.humidity
        );

        scd4x_sensor
            .stop_periodic_measurement()
            .await
            .expect("failed to stop periodic SCD4x measurement");

        scd4x_sensor
            .start_low_power_periodic_measurements()
            .await
            .expect("failed to start low-power periodic SCD4x measurement");

        let mut low_power_data_ready = false;
        for _attempt_index in 0..LOW_POWER_READY_POLL_RETRIES {
            if scd4x_sensor
                .data_ready_status()
                .await
                .expect("failed to read low-power SCD4x data_ready_status")
            {
                low_power_data_ready = true;
                break;
            }

            Timer::after(Duration::from_millis(LOW_POWER_READY_POLL_INTERVAL_MS)).await;
        }

        defmt::assert!(low_power_data_ready);

        let low_power_measurement = scd4x_sensor
            .measurement()
            .await
            .expect("failed to read low-power periodic SCD4x measurement");

        assert_measurement_is_sane(
            low_power_measurement.co2,
            low_power_measurement.temperature,
            low_power_measurement.humidity,
        );

        info!(
            "low-power: co2={}ppm temp={=f32}C rh={=f32}%",
            low_power_measurement.co2,
            low_power_measurement.temperature,
            low_power_measurement.humidity
        );

        scd4x_sensor
            .stop_periodic_measurement()
            .await
            .expect("failed to stop low-power periodic SCD4x measurement");
    }
}
