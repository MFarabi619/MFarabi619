//! `describe("SCD30 CO2 Sensor")`
//!
//! Probes both I2C buses for an SCD30 at 0x61 and pulls a single
//! measurement through the same firmware code the microvisor runs in
//! production (`ceratina::programs::carbon_dioxide::{probe_scd30, read_scd30}`).

#![no_std]
#![no_main]

#[path = "common/mod.rs"]
mod common;

use defmt::info;

use common::{Device, tasks};

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::setup]
fn setup() {
    rtt_target::rtt_init_defmt!();
}

#[cfg(test)]
#[embedded_test::tests(default_timeout = 120, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== SCD30 CO2 Sensor — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user reads a physically plausible CO2 measurement from the device SCD30")`
    #[test]
    #[timeout(120)]
    async fn user_reads_a_plausible_co2_measurement_from_device_scd30(
        mut device: Device,
    ) -> Result<(), &'static str> {
        common::setup::delay_seconds(1).await;

        let co2_reading = tasks::carbon_dioxide::read_scd30_measurement(&mut device).await?;
        tasks::carbon_dioxide::assert_reading_is_physically_plausible(&co2_reading)?;

        info!(
            "SCD30 reading co2_ppm={=f32} temperature={=f32} humidity={=f32}",
            co2_reading.co2_ppm, co2_reading.temperature, co2_reading.humidity
        );
        Ok(())
    }
}
