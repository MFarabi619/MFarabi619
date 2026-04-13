//! Temperature and humidity sensor program.
//!
//! Reads from an SHT31-compatible I2C sensor and logs to the SD card CSV.

use core::fmt::Write;

use defmt::info;
use embassy_time::{Duration, Instant, Ticker, Timer};
use esp_hal::i2c::master::I2c;
use heapless::String as HeaplessString;

use crate::hardware::i2c::{SENSOR_MEASUREMENT_COMMAND, calculate_crc8};
use crate::filesystems::sd;

// ─── Sensor reading ────────────────────────────────────────────────────────────

fn convert_temperature(raw: u16) -> f32 {
    -45.0 + 175.0 * (raw as f32 / 65535.0)
}

fn convert_humidity(raw: u16) -> f32 {
    100.0 * (raw as f32 / 65535.0)
}

async fn read_once(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
    sensor_address: u8,
) -> Result<(f32, f32), &'static str> {
    i2c_bus
        .write_async(sensor_address, &SENSOR_MEASUREMENT_COMMAND)
        .await
        .map_err(|_| "failed to send measurement command")?;

    Timer::after(Duration::from_millis(60)).await;

    let mut buf = [0_u8; 6];
    i2c_bus
        .read_async(sensor_address, &mut buf)
        .await
        .map_err(|_| "failed to read measurement bytes")?;

    let temp_bytes = [buf[0], buf[1]];
    let hum_bytes = [buf[3], buf[4]];

    if buf[2] != calculate_crc8(&temp_bytes) {
        return Err("temperature CRC mismatch");
    }
    if buf[5] != calculate_crc8(&hum_bytes) {
        return Err("humidity CRC mismatch");
    }

    Ok((
        convert_temperature(u16::from_be_bytes(temp_bytes)),
        convert_humidity(u16::from_be_bytes(hum_bytes)),
    ))
}

// ─── Data logging task ─────────────────────────────────────────────────────────

#[embassy_executor::task]
pub async fn task(
    mut i2c_bus: I2c<'static, esp_hal::Async>,
    sensor_address: u8,
    sensor_name: &'static str,
) {
    let mut sampling_interval = Ticker::every(Duration::from_secs(
        crate::config::data_logger::SAMPLING_INTERVAL_SECS,
    ));

    loop {
        sampling_interval.next().await;

        match read_once(&mut i2c_bus, sensor_address).await {
            Ok((temperature_celsius, relative_humidity_percent)) => {
                let timestamp_millis = Instant::now().as_millis();
                let mut data_csv_line = HeaplessString::<192>::new();

                if write!(
                    data_csv_line,
                    "{},{:.2},{:.2},,,,,,,,\n",
                    timestamp_millis, temperature_celsius, relative_humidity_percent
                )
                .is_err()
                {
                    info!("failed to format data.csv row");
                    continue;
                }

                if let Err(msg) = sd::append_data_csv_line(data_csv_line.as_str()) {
                    info!("failed to append data.csv row: {}", msg);
                } else {
                    info!(
                        "logged {} sample: temperature={}C humidity={}%%",
                        sensor_name, temperature_celsius, relative_humidity_percent
                    );
                }
            }
            Err(msg) => {
                info!("failed to read {} sensor: {}", sensor_name, msg);
            }
        }
    }
}
