//! I2C tasks — bus scan + human-friendly address labeling.

use defmt::info;
use esp_hal::i2c::master::I2c;

use crate::common::setup::Device;

pub const SCAN_ADDRESS_MIN: u8 = 0x03;
pub const SCAN_ADDRESS_MAX: u8 = 0x77;

/// Best-guess human label for a known 7-bit I2C address. Returns a
/// generic "unknown" for unmapped addresses so scan output still reads
/// as a labeled list.
pub fn label_for_address(address: u8) -> &'static str {
    match address {
        0x44 => "SHT31 temperature/humidity",
        0x45 => "SHT31 temperature/humidity (alt)",
        0x50..=0x57 => "AT24C32 EEPROM (DS3231 breakout piggyback)",
        0x58 => "SGP30 VOC",
        0x5a => "CCS811 VOC",
        0x61 => "SCD30 CO2",
        0x62 => "SCD4x CO2",
        0x68 => "DS3231 / DS1307 RTC (or MPU-6050)",
        0x70 => "TCA9548A I2C mux",
        0x76 => "BME280/BMP280 pressure (alt)",
        0x77 => "BME280/BMP280 pressure",
        _ => "unknown",
    }
}

pub struct BusScanOutcome {
    pub bus_label: &'static str,
    pub found_addresses: heapless::Vec<u8, 32>,
}

/// Scan a single blocking I2C bus across the canonical 7-bit device
/// address range. Logs every ACKing address with its best-guess label
/// via `defmt::info!`. Returns the collected addresses so callers can
/// make further assertions.
pub fn scan_blocking_bus(
    bus_label: &'static str,
    i2c_bus: &mut I2c<'_, esp_hal::Blocking>,
) -> BusScanOutcome {
    info!(
        "user scans bus={=str} address_range=0x{=u8:02x}..=0x{=u8:02x}",
        bus_label, SCAN_ADDRESS_MIN, SCAN_ADDRESS_MAX
    );

    let mut found_addresses: heapless::Vec<u8, 32> = heapless::Vec::new();
    for candidate_address in SCAN_ADDRESS_MIN..=SCAN_ADDRESS_MAX {
        if i2c_bus.write(candidate_address, &[]).is_ok() {
            info!(
                "  bus={=str} address=0x{=u8:02x} label={=str}",
                bus_label,
                candidate_address,
                label_for_address(candidate_address)
            );
            let _ = found_addresses.push(candidate_address);
        }
    }

    info!(
        "bus={=str} scan complete found_count={=usize}",
        bus_label,
        found_addresses.len()
    );

    BusScanOutcome {
        bus_label,
        found_addresses,
    }
}

/// Borrows `device.i2c_bus_0` and `device.i2c_bus_1` in place and scans
/// both. Returns `Err` if either bus slot has already been consumed.
pub fn scan_both_buses(
    device: &mut Device,
) -> Result<(BusScanOutcome, BusScanOutcome), &'static str> {
    let i2c_bus_0 = device
        .i2c_bus_0
        .as_mut()
        .ok_or("device I2C bus 0 already consumed")?;
    let i2c_bus_0_outcome = scan_blocking_bus("i2c.0", i2c_bus_0);

    let i2c_bus_1 = device
        .i2c_bus_1
        .as_mut()
        .ok_or("device I2C bus 1 already consumed")?;
    let i2c_bus_1_outcome = scan_blocking_bus("i2c.1", i2c_bus_1);

    Ok((i2c_bus_0_outcome, i2c_bus_1_outcome))
}
