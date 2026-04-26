//! `describe("SD Card Webpage")`
//!
//! Manual integration test. The device:
//!   1. mounts the SD card
//!   2. ensures `/index.htm` exists (writes a minimal placeholder if absent)
//!   3. starts its WiFi access point
//!   4. starts a tiny HTTP/1.0 server on port 80 backed by the SD card
//!
//! The test then waits for an external HTTP GET to land at `/`. Pass
//! criterion: a request hits the device within the 5-minute timeout.

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
        info!("=== SD Card Webpage — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user can load index.htm from the device SD card over WiFi")`
    #[test]
    #[timeout(300)]
    async fn user_loads_index_html_from_device_sd_card_over_wifi(
        mut device: Device,
    ) -> Result<(), &'static str> {
        // SAFETY: every embedded-test runs inside an `esp_rtos::embassy::Executor`,
        // so the current async context is owned by an Embassy executor.
        let embassy_spawner =
            unsafe { embassy_executor::Spawner::for_current_executor() }.await;

        tasks::sd_card::mount(&mut device)?;
        tasks::sd_card::ensure_index_html(&mut device)?;
        tasks::wifi::start_access_point(&mut device, embassy_spawner).await?;
        tasks::http::start_server_serving_sd(&mut device, embassy_spawner)?;

        info!(">>> ACTION REQUIRED <<<");
        info!(
            ">>> 1. Connect your phone/laptop to WiFi ssid={=str}",
            tasks::wifi::DEFAULT_ACCESS_POINT_SSID
        );
        info!(
            ">>> 2. Password: {=str}",
            tasks::wifi::DEFAULT_ACCESS_POINT_PASSWORD
        );
        info!(">>> 3. Open http://192.168.4.1/ in your browser");
        info!(">>> Test will time out in 5 minutes if no request lands");

        tasks::http::wait_for_first_request(&mut device).await?;

        Ok(())
    }
}
