//! `describe("I2C Bus Scanner")`
//!
//! Scans both I2C buses (wired per `config::i2c`)
//! for devices in the 7-bit 0x03..=0x77 range and prints each ACKing
//! address with a best-guess label via defmt. Flash this test when you
//! want to find out which bus a physical sensor is wired to.
//!
//! Canonical pin assignments come from `firmware/src/config.rs`:
//!   i2c.0 → sda=GPIO8  scl=GPIO9
//!   i2c.1 → sda=GPIO17 scl=GPIO18
//!
//! `#[ignore]` by default (requires hardware); opt in with
//! `--include-ignored`.

#![no_std]
#![no_main]

#[path = "common/mod.rs"]
mod common;
use common::{Device, tasks};
use defmt::info;

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::setup]
fn setup() {
    rtt_target::rtt_init_defmt!();
}

#[cfg(test)]
#[embedded_test::tests(default_timeout = 15, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== I2C Bus Scanner — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user scans both buses and sees every wired I2C device")`
    #[test]
    async fn user_scans_both_buses_and_sees_every_wired_i2c_device(
        mut device: Device,
    ) -> Result<(), &'static str> {
        common::setup::delay_seconds(1).await;

        let (bus_0, bus_1) = tasks::i2c::scan_both_buses(&mut device)?;
        let total = bus_0.found_addresses.len() + bus_1.found_addresses.len();

        info!("BUS     ADDR    DEVICE");
        for addr in bus_0.found_addresses.iter() {
            info!(
                "i2c.0   0x{=u8:02x}    {=str}",
                *addr,
                firmware::hardware::i2c::device_name_at(*addr)
            );
        }
        for addr in bus_1.found_addresses.iter() {
            info!(
                "i2c.1   0x{=u8:02x}    {=str}",
                *addr,
                firmware::hardware::i2c::device_name_at(*addr)
            );
        }

        info!(
            "scan summary: bus0={=usize} bus1={=usize} total={=usize}",
            bus_0.found_addresses.len(),
            bus_1.found_addresses.len(),
            total,
        );

        defmt::assert!(total > 0, "no I2C devices found on either bus");
        Ok(())
    }

    /// `it("user probes for TCA9548A mux on bus 1")`
    #[test]
    async fn user_probes_mux_on_bus_1(
        mut device: Device,
    ) -> Result<(), &'static str> {
        if !tasks::i2c::is_mux_present(&mut device) {
            info!("mux not present on this board — skipping");
            return Ok(());
        }
        info!("TCA9548A mux detected at 0x70 on i2c.1");
        Ok(())
    }

    /// `it("user selects a mux channel and verifies the mask")`
    #[test]
    async fn user_selects_mux_channel_and_verifies(
        mut device: Device,
    ) -> Result<(), &'static str> {
        if !tasks::i2c::is_mux_present(&mut device) {
            info!("mux not present — skipping");
            return Ok(());
        }

        let bus = device.i2c_bus_1.as_mut().ok_or("i2c bus 1 consumed")?;

        tasks::i2c::select_mux_channel(bus, 0)?;
        let mask = tasks::i2c::access_channel_mask(bus)?;
        defmt::assert_eq!(mask & (1 << 0), 1, "bit 0 should be set after select(0)");

        tasks::i2c::select_mux_channel(bus, 3)?;
        let mask = tasks::i2c::access_channel_mask(bus)?;
        defmt::assert_eq!(mask & (1 << 3), (1 << 3), "bit 3 should be set after select(3)");
        defmt::assert_eq!(mask & (1 << 0), 0, "bit 0 should be clear after select(3)");

        tasks::i2c::disable_all_channels(bus)?;
        info!("mux channel select and verify passed");
        Ok(())
    }

    /// `it("user disables all mux channels and sees mask 0x00")`
    #[test]
    async fn user_disables_all_mux_channels(
        mut device: Device,
    ) -> Result<(), &'static str> {
        if !tasks::i2c::is_mux_present(&mut device) {
            info!("mux not present — skipping");
            return Ok(());
        }

        let bus = device.i2c_bus_1.as_mut().ok_or("i2c bus 1 consumed")?;

        tasks::i2c::select_mux_channel(bus, 0)?;
        tasks::i2c::select_mux_channel(bus, 3)?;
        tasks::i2c::select_mux_channel(bus, 7)?;

        tasks::i2c::disable_all_channels(bus)?;
        let mask = tasks::i2c::access_channel_mask(bus)?;
        defmt::assert_eq!(mask, 0x00, "mask should be 0x00 after disable all");

        info!("disable all channels verified");
        Ok(())
    }

    /// `it("user enables then disables a single mux channel")`
    #[test]
    async fn user_enables_then_disables_single_channel(
        mut device: Device,
    ) -> Result<(), &'static str> {
        if !tasks::i2c::is_mux_present(&mut device) {
            info!("mux not present — skipping");
            return Ok(());
        }

        let bus = device.i2c_bus_1.as_mut().ok_or("i2c bus 1 consumed")?;

        tasks::i2c::disable_all_channels(bus)?;

        tasks::i2c::select_mux_channel(bus, 2)?;
        let mask = tasks::i2c::access_channel_mask(bus)?;
        defmt::assert_eq!(mask & (1 << 2), (1 << 2), "bit 2 should be set");

        tasks::i2c::disable_all_channels(bus)?;
        let mask = tasks::i2c::access_channel_mask(bus)?;
        defmt::assert_eq!(mask, 0x00, "mask should be 0x00 after disable");

        info!("enable/disable roundtrip verified");
        Ok(())
    }
}
