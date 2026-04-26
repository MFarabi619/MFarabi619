//! I2C tasks — bus scan, mux helpers, device labeling.

use defmt::info;
use esp_hal::i2c::master::I2c;
use ceratina::hardware::i2c;

use crate::common::setup::Device;

pub const SCAN_ADDRESS_MIN: u8 = 0x03;
pub const SCAN_ADDRESS_MAX: u8 = 0x77;
pub const MUX_ADDR: u8 = 0x70;

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
                i2c::device_name_at(candidate_address)
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

pub fn is_mux_present(device: &mut Device) -> bool {
    let bus = match device.i2c_bus_1.as_mut() {
        Some(bus) => bus,
        None => return false,
    };
    bus.write(MUX_ADDR, &[]).is_ok()
}

pub fn select_mux_channel(
    i2c_bus: &mut I2c<'_, esp_hal::Blocking>,
    channel: u8,
) -> Result<(), &'static str> {
    let mask = 1u8 << channel;
    i2c_bus
        .write(MUX_ADDR, &[mask])
        .map_err(|_| "device: failed to select mux channel")
}

pub fn access_channel_mask(
    i2c_bus: &mut I2c<'_, esp_hal::Blocking>,
) -> Result<u8, &'static str> {
    let mut buf = [0u8; 1];
    i2c_bus
        .read(MUX_ADDR, &mut buf)
        .map_err(|_| "device: failed to read mux channel mask")?;
    Ok(buf[0])
}

pub fn disable_all_channels(
    i2c_bus: &mut I2c<'_, esp_hal::Blocking>,
) -> Result<(), &'static str> {
    i2c_bus
        .write(MUX_ADDR, &[0x00])
        .map_err(|_| "device: failed to disable all mux channels")
}
