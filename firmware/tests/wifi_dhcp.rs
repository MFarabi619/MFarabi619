//! `describe("Wi-Fi DHCP")`
//!
//! Station-mode smoke test: the device joins the configured home WiFi,
//! performs DHCP, and reports an IPv4 address. `#[ignore]` because it
//! depends on an external AP being reachable; opt in with
//! `--include-ignored`.

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
#[embedded_test::tests(default_timeout = 45, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== Wi-Fi DHCP — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user joins home WiFi and receives a DHCP lease")`
    #[test]
    #[timeout(30)]
    async fn user_joins_home_wifi_and_receives_dhcp_lease(
        mut device: Device,
    ) -> Result<(), &'static str> {
        // SAFETY: every embedded-test runs inside an `esp_rtos::embassy::Executor`.
        let embassy_spawner =
            unsafe { embassy_executor::Spawner::for_current_executor() }.await;

        tasks::wifi::connect_to_home_access_point(&mut device, embassy_spawner).await?;

        let embassy_network_stack = device
            .embassy_network_stack
            .ok_or("device: embassy-net stack missing after DHCP")?;
        let ipv4_config = embassy_network_stack
            .config_v4()
            .ok_or("device: DHCP completed but no IPv4 config available")?;
        info!(
            "DHCP address acquired ipv4={=[u8]:?}",
            ipv4_config.address.address().octets()
        );
        Ok(())
    }
}
