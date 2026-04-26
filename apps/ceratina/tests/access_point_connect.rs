//! `describe("Access Point Connection")`
//!
//! Manual integration test. The device starts its WiFi access point;
//! the test waits for an external client (the user's phone or laptop)
//! to associate. Pass criterion: a station joins within the 5-minute
//! `#[timeout]`. Failure: timeout, or the AP fails to come up.

#![no_std]
#![no_main]

extern crate alloc;

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
#[embedded_test::tests(default_timeout = 30, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== Access Point Connection — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user can connect their phone to the device access point")`
    #[test]
    #[timeout(300)]
    async fn user_connects_their_phone_to_device_access_point(
        mut device: Device,
    ) -> Result<(), &'static str> {
        // SAFETY: every embedded-test runs inside an `esp_rtos::embassy::Executor`,
        // so the current async context is owned by an Embassy executor.
        let embassy_spawner =
            unsafe { embassy_executor::Spawner::for_current_executor() }.await;

        tasks::wifi::start_access_point(&mut device, embassy_spawner).await?;

        info!(">>> ACTION REQUIRED <<<");
        info!(
            ">>> Connect your phone or laptop to WiFi ssid={=str}",
            tasks::wifi::DEFAULT_ACCESS_POINT_SSID
        );
        info!(
            ">>> Password: {=str}",
            tasks::wifi::DEFAULT_ACCESS_POINT_PASSWORD
        );
        info!(">>> Test will time out in 5 minutes if no client connects");

        tasks::wifi::wait_for_first_station(&mut device).await?;

        Ok(())
    }
}
