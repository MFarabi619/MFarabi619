//! CO₂ sensor tasks. Thin wrappers over
//! `ceratina::programs::carbon_dioxide` so tests can reuse the exact
//! probe / read code the microvisor runs in production.

use defmt::info;
use esp_hal::i2c::master::I2c;
use ceratina::programs::carbon_dioxide::{probe_scd30, probe_scd4x, read_scd30, read_scd4x};
use ceratina::sensors::manager::{self, Co2Reading};

use crate::common::setup::Device;

fn scd30_i2c_address() -> u8 {
    manager::carbon_dioxide_address_scd30()
}

fn scd4x_i2c_address() -> u8 {
    manager::carbon_dioxide_address_scd4x()
}

fn device_acks_at_address(
    i2c_bus: &mut I2c<'_, esp_hal::Blocking>,
    target_address: u8,
) -> bool {
    i2c_bus.write(target_address, &[]).is_ok()
}

fn locate_target_bus(
    device: &mut Device,
    target_address: u8,
    sensor_label: &'static str,
) -> Result<&'static str, &'static str> {
    if let Some(bus_zero) = device.i2c_bus_0.as_mut()
        && device_acks_at_address(bus_zero, target_address)
    {
        info!(
            "{=str} detected bus=i2c.0 address=0x{=u8:02x}",
            sensor_label, target_address
        );
        return Ok("i2c.0");
    }
    if let Some(bus_one) = device.i2c_bus_1.as_mut()
        && device_acks_at_address(bus_one, target_address)
    {
        info!(
            "{=str} detected bus=i2c.1 address=0x{=u8:02x}",
            sensor_label, target_address
        );
        return Ok("i2c.1");
    }
    Err("device: CO2 sensor did not ACK on either I2C bus")
}

fn take_blocking_bus_by_label(
    device: &mut Device,
    bus_label: &'static str,
) -> Option<I2c<'static, esp_hal::Blocking>> {
    match bus_label {
        "i2c.0" => device.i2c_bus_0.take(),
        "i2c.1" => device.i2c_bus_1.take(),
        _ => None,
    }
}

/// Probe for an SCD30 on either I2C bus, do a full measurement read,
/// and return the reading. Consumes the winning bus for the lifetime
/// of the test (the SCD30 driver holds it).
pub async fn read_scd30_measurement(
    device: &mut Device,
) -> Result<Co2Reading, &'static str> {
    info!("user reads a CO2 measurement from the device SCD30");

    let bus_label = locate_target_bus(device, scd30_i2c_address(), "SCD30")?;
    let blocking_bus = take_blocking_bus_by_label(device, bus_label)
        .ok_or("device: SCD30 I2C bus slot empty after locate")?;
    let async_bus = blocking_bus.into_async();

    let mut scd30_sensor = probe_scd30(async_bus)
        .await
        .map_err(|_returned_bus| "device: SCD30 probe failed after ACK (bad firmware handshake)")?;

    read_scd30(&mut scd30_sensor)
        .await
        .map_err(|_unit_error| "device: SCD30 measurement read failed (polling timeout or CRC error)")
}

/// Probe for an SCD4x on either I2C bus, do a full measurement read,
/// and return the reading. Same ownership semantics as SCD30.
pub async fn read_scd4x_measurement(
    device: &mut Device,
) -> Result<Co2Reading, &'static str> {
    info!("user reads a CO2 measurement from the device SCD4x");

    let bus_label = locate_target_bus(device, scd4x_i2c_address(), "SCD4x")?;
    let blocking_bus = take_blocking_bus_by_label(device, bus_label)
        .ok_or("device: SCD4x I2C bus slot empty after locate")?;
    let async_bus = blocking_bus.into_async();

    let mut scd4x_sensor = probe_scd4x(async_bus)
        .await
        .map_err(|_returned_bus| "device: SCD4x probe failed after ACK (bad firmware handshake)")?;

    read_scd4x(&mut scd4x_sensor)
        .await
        .map_err(|_unit_error| "device: SCD4x measurement read failed (polling timeout or CRC error)")
}

pub fn assert_reading_is_physically_plausible(
    co2_reading: &Co2Reading,
) -> Result<(), &'static str> {
    if !co2_reading.co2_ppm.is_finite() {
        return Err("device: CO2 ppm is NaN or infinite");
    }
    if co2_reading.co2_ppm < 0.0 || co2_reading.co2_ppm > 40_000.0 {
        return Err("device: CO2 ppm outside physically plausible range [0, 40000]");
    }
    if !co2_reading.temperature.is_finite() {
        return Err("device: temperature is NaN or infinite");
    }
    if co2_reading.temperature < -40.0 || co2_reading.temperature > 125.0 {
        return Err("device: temperature outside physically plausible range [-40, 125]");
    }
    if !co2_reading.humidity.is_finite() {
        return Err("device: humidity is NaN or infinite");
    }
    if co2_reading.humidity < 0.0 || co2_reading.humidity > 100.5 {
        return Err("device: humidity outside physically plausible range [0, 100.5]");
    }
    Ok(())
}
