//! `describe("Microvisor Boot Smoke")`
//!
//! End-to-end smoke test for the `boot_device()` happy path: the
//! device initialises embassy + esp_rtos, mounts the SD card, creates
//! both I2C buses, and spins up the WiFi controller. A passing test
//! means every non-sensor ability of the device is reachable.

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
#[embedded_test::tests(default_timeout = 15, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== Microvisor Boot Smoke — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user boots the device and every ability is reachable")`
    #[test]
    async fn user_boots_the_device_and_every_ability_is_reachable(
        device: Device,
    ) -> Result<(), &'static str> {
        defmt::assert!(
            device.wifi_controller.is_some(),
            "boot_device left wifi_controller empty"
        );
        defmt::assert!(
            device.wifi_interfaces.is_some(),
            "boot_device left wifi_interfaces empty"
        );
        defmt::assert!(
            device.i2c_bus_0.is_some(),
            "boot_device left i2c_bus_0 empty"
        );
        defmt::assert!(
            device.i2c_bus_1.is_some(),
            "boot_device left i2c_bus_1 empty"
        );
        defmt::assert!(
            device.embassy_network_stack.is_none(),
            "boot_device should leave embassy_network_stack empty until wifi tasks bring it up"
        );
        defmt::assert!(
            device.embassy_network_seed != 0,
            "boot_device produced a zero embassy_network_seed (RNG bug?)"
        );
        Ok(())
    }
}
