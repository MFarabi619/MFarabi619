use embassy_time::{Duration, Timer};
use esp_hal::i2c::master::I2c;

use crate::drivers::i2c::{SENSOR_MEASUREMENT_COMMAND, calculate_crc8};

pub fn convert_temperature_celsius(temperature_raw_value: u16) -> f32 {
    -45.0 + 175.0 * (temperature_raw_value as f32 / 65535.0)
}

pub fn convert_relative_humidity_percent(humidity_raw_value: u16) -> f32 {
    100.0 * (humidity_raw_value as f32 / 65535.0)
}

pub async fn read_once(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
    sensor_address: u8,
) -> Result<(f32, f32), &'static str> {
    i2c_bus
        .write_async(sensor_address, &SENSOR_MEASUREMENT_COMMAND)
        .await
        .map_err(|_| "failed to send measurement command")?;

    Timer::after(Duration::from_millis(60)).await;

    let mut measurement_buffer = [0_u8; 6];
    i2c_bus
        .read_async(sensor_address, &mut measurement_buffer)
        .await
        .map_err(|_| "failed to read measurement bytes")?;

    let temperature_bytes = [measurement_buffer[0], measurement_buffer[1]];
    let humidity_bytes = [measurement_buffer[3], measurement_buffer[4]];
    let received_temperature_crc = measurement_buffer[2];
    let received_humidity_crc = measurement_buffer[5];

    if received_temperature_crc != calculate_crc8(&temperature_bytes) {
        return Err("temperature CRC mismatch");
    }
    if received_humidity_crc != calculate_crc8(&humidity_bytes) {
        return Err("humidity CRC mismatch");
    }

    let temperature_raw_value = u16::from_be_bytes(temperature_bytes);
    let humidity_raw_value = u16::from_be_bytes(humidity_bytes);

    Ok((
        convert_temperature_celsius(temperature_raw_value),
        convert_relative_humidity_percent(humidity_raw_value),
    ))
}
