//! `describe("Hello (smoke)")`
//!
//! Trivial smoke test that proves the embedded-test runner is wired up
//! and embassy is alive.

#![no_std]
#![no_main]

#[path = "common/mod.rs"]
mod common;

use defmt::info;

use common::Device;

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::setup]
fn setup() {
    rtt_target::rtt_init_defmt!();
}

#[cfg(test)]
#[embedded_test::tests(default_timeout = 5, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== Hello (smoke) — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user observes that arithmetic still works")`
    #[test]
    async fn user_observes_that_arithmetic_still_works(
        _device: Device,
    ) -> Result<(), &'static str> {
        embassy_time::Timer::after(embassy_time::Duration::from_millis(10)).await;

        if 1 + 1 != 2 {
            return Err("device: arithmetic broke; nothing else can be trusted");
        }
        Ok(())
    }
}
