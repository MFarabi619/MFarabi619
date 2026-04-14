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

    /// `it("user scans both buses and sees every wired I2C device with a label")`
    #[test]
    async fn user_scans_both_buses_and_sees_every_wired_i2c_device(
        mut device: Device,
    ) -> Result<(), &'static str> {
        // Allow the device's sensor rail to settle. The `boot_device()`
        // path doesn't flip any power-enable GPIO yet — the sensors are
        // expected to be powered externally or from the default-high
        // rail. If you see empty scans, double-check the sensor power
        // relay is on.
        common::setup::delay_seconds(1).await;

        let (i2c_bus_0_outcome, i2c_bus_1_outcome) = tasks::i2c::scan_both_buses(&mut device)?;

        info!(
            "scan summary bus0_count={=usize} bus1_count={=usize} total={=usize}",
            i2c_bus_0_outcome.found_addresses.len(),
            i2c_bus_1_outcome.found_addresses.len(),
            i2c_bus_0_outcome.found_addresses.len() + i2c_bus_1_outcome.found_addresses.len(),
        );

        // We deliberately don't assert that either bus found anything —
        // this test is a discovery tool, not a pass/fail gate. The
        // point is to read the defmt log and see which bus each sensor
        // lives on. If you want to enforce a specific topology (e.g.
        // "SCD30 must be on i2c.1 at 0x61"), add a dedicated test that
        // calls `scan_both_buses` and checks the outcomes.
        Ok(())
    }
}
