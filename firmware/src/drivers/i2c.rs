use esp_hal::i2c::master::I2c;

pub const I2C_BUS_FREQUENCY_KHZ: u32 = 100;
pub const I2C_MUX_ADDRESS: u8 = 0x70;
pub const SENSOR_CANDIDATE_ADDRESSES: [u8; 4] = [0x44, 0x45, 0x46, 0x47];
pub const SENSOR_MEASUREMENT_COMMAND: [u8; 2] = [0x24, 0x00];

pub async fn select_mux_channel(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
    mux_channel: u8,
) -> Result<(), &'static str> {
    if mux_channel > 7 {
        return Err("mux channel out of range");
    }

    let mux_channel_mask = 1_u8 << mux_channel;
    i2c_bus
        .write_async(I2C_MUX_ADDRESS, &[mux_channel_mask])
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
