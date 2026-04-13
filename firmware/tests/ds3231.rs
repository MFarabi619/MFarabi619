//! `describe("DS3231 Real-Time Clock")`
//!
//! Probes both I2C buses for a DS3231 at 0x68 and reads its current
//! datetime. The test doesn't pre-commit to a specific bus — it picks
//! the one that ACKs — which is exactly what you need while the
//! hardware is still being wired.

#![no_std]
#![no_main]

#[path = "common/mod.rs"]
mod common;

use defmt::info;
use ds323x::{Datelike, Timelike};

use common::{Device, tasks};

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::setup]
fn setup() {
    rtt_target::rtt_init_defmt!();
}

#[cfg(test)]
#[embedded_test::tests(default_timeout = 10, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== DS3231 Real-Time Clock — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user reads a plausible datetime from the device DS3231")`
    #[test]
    async fn user_reads_a_plausible_datetime_from_device_ds3231(
        mut device: Device,
    ) -> Result<(), &'static str> {
        common::setup::delay_seconds(1).await;

        let current_datetime = tasks::ds3231::read_current_datetime(&mut device)?;

        defmt::assert!(
            (1..=12).contains(&current_datetime.month()),
            "DS3231 month {=u32} is out of range",
            current_datetime.month()
        );
        defmt::assert!(
            (1..=31).contains(&current_datetime.day()),
            "DS3231 day {=u32} is out of range",
            current_datetime.day()
        );
        defmt::assert!(
            current_datetime.hour() <= 23,
            "DS3231 hour {=u32} is out of range",
            current_datetime.hour()
        );
        defmt::assert!(
            current_datetime.minute() <= 59,
            "DS3231 minute {=u32} is out of range",
            current_datetime.minute()
        );
        defmt::assert!(
            current_datetime.second() <= 59,
            "DS3231 second {=u32} is out of range",
            current_datetime.second()
        );
        Ok(())
    }
}
