use esp_hal::i2c::master::{Config as I2cConfig, I2c};
use esp_hal::time::Rate;

use crate::config;

pub const SENSOR_CANDIDATE_ADDRESSES: [u8; 4] = [0x44, 0x45, 0x46, 0x47];
pub const SENSOR_MEASUREMENT_COMMAND: [u8; 2] = [0x24, 0x00];

pub fn initialize_bus_0(
    peripheral: esp_hal::peripherals::I2C0<'static>,
    sda: esp_hal::peripherals::GPIO8<'static>,
    scl: esp_hal::peripherals::GPIO9<'static>,
) -> I2c<'static, esp_hal::Async> {
    I2c::new(
        peripheral,
        I2cConfig::default().with_frequency(Rate::from_khz(config::i2c::FREQUENCY_KHZ)),
    )
    .unwrap()
    .with_sda(sda)
    .with_scl(scl)
    .into_async()
}

pub fn initialize_bus_1(
    peripheral: esp_hal::peripherals::I2C1<'static>,
    sda: esp_hal::peripherals::GPIO17<'static>,
    scl: esp_hal::peripherals::GPIO18<'static>,
) -> I2c<'static, esp_hal::Async> {
    I2c::new(
        peripheral,
        I2cConfig::default().with_frequency(Rate::from_khz(config::i2c::FREQUENCY_KHZ)),
    )
    .unwrap()
    .with_sda(sda)
    .with_scl(scl)
    .into_async()
}

pub async fn select_mux_channel(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
    mux_channel: u8,
) -> Result<(), &'static str> {
    if mux_channel > 7 {
        return Err("mux channel out of range");
    }

    let mux_channel_mask = 1_u8 << mux_channel;
    i2c_bus
        .write_async(config::i2c::MUX_ADDR, &[mux_channel_mask])
        .await
        .map_err(|_| "failed to select I2C mux channel")?;
    Ok(())
}

pub async fn discover_sensor_address(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
) -> Option<u8> {
    for sensor_candidate_address in SENSOR_CANDIDATE_ADDRESSES {
        if i2c_bus
            .write_async(sensor_candidate_address, &[])
            .await
            .is_ok()
        {
            return Some(sensor_candidate_address);
        }
    }

    None
}

pub fn calculate_crc8(data_bytes: &[u8]) -> u8 {
    let mut crc_value: u8 = 0xFF;

    for data_byte in data_bytes {
        crc_value ^= *data_byte;
        for _ in 0..8 {
            crc_value = if (crc_value & 0x80) != 0 {
                (crc_value << 1) ^ 0x31
            } else {
                crc_value << 1
            };
        }
    }

    crc_value
}
