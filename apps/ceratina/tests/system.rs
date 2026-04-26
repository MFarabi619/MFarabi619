//! `describe("System")`
//!
//! Hardware observability tests — mirrors C++ `hardware/system_test.cpp`.
//! Tests what the hardware reports: heap, CPU frequency, chip version,
//! reset reason.

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
        info!("=== System — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user observes heap reports free memory")`
    #[test]
    async fn user_observes_heap_reports_free_memory(
        _device: Device,
    ) -> Result<(), &'static str> {
        let free = esp_alloc::HEAP.free();
        let used = esp_alloc::HEAP.used();
        let total = free + used;

        info!(
            "heap: free={=usize} used={=usize} total={=usize} KiB",
            free / 1024,
            used / 1024,
            total / 1024
        );

        defmt::assert!(free > 0, "heap reports zero free bytes");
        defmt::assert!(total >= 64 * 1024, "heap total below 64 KiB minimum");
        Ok(())
    }

    /// `it("user observes CPU frequency is 240 MHz")`
    #[test]
    async fn user_observes_cpu_frequency_is_240_mhz(
        _device: Device,
    ) -> Result<(), &'static str> {
        let cpu_hz = esp_hal::clock::cpu_clock().as_hz();
        let cpu_mhz = cpu_hz / 1_000_000;

        info!("CPU: {=u32} MHz", cpu_mhz);

        defmt::assert_eq!(cpu_mhz, 240, "ESP32-S3 should run at 240 MHz");
        Ok(())
    }

    /// `it("user observes chip version is readable")`
    #[test]
    async fn user_observes_chip_version_is_readable(
        _device: Device,
    ) -> Result<(), &'static str> {
        let major = esp_hal::efuse::major_chip_version();
        let minor = esp_hal::efuse::minor_chip_version();

        info!("chip version: major={=u8} minor={=u8}", major, minor);

        defmt::assert!(major > 0 || minor > 0, "chip version is 0.0");
        Ok(())
    }

    /// `it("user observes reset reason is available")`
    #[test]
    async fn user_observes_reset_reason_is_available(
        _device: Device,
    ) -> Result<(), &'static str> {
        let reason = esp_hal::system::reset_reason();

        defmt::assert!(reason.is_some(), "reset reason is None");
        info!("reset reason is present");
        Ok(())
    }

    /// `it("user observes chip identity matches ESP32-S3")`
    #[test]
    async fn user_observes_chip_identity(
        _device: Device,
    ) -> Result<(), &'static str> {
        let chip = esp_hal::chip!();

        info!("chip={=str}", chip);

        defmt::assert_eq!(chip, "esp32s3");
        Ok(())
    }

    /// `it("user observes firmware app descriptor is valid")`
    #[test]
    async fn user_observes_app_descriptor_is_valid(
        _device: Device,
    ) -> Result<(), &'static str> {
        defmt::assert_eq!(ESP_APP_DESC.magic_word(), 0xABCD5432, "bad magic word");

        let version = ESP_APP_DESC.version();
        let project = ESP_APP_DESC.project_name();
        let idf_ver = ESP_APP_DESC.idf_ver();
        let build_time = ESP_APP_DESC.time();
        let build_date = ESP_APP_DESC.date();

        info!("version={=str} project={=str} idf={=str}", version, project, idf_ver);
        info!("build_time={=str} build_date={=str}", build_time, build_date);

        defmt::assert!(!version.is_empty(), "version is empty");
        defmt::assert!(!project.is_empty(), "project name is empty");
        defmt::assert!(!idf_ver.is_empty(), "idf version is empty");
        Ok(())
    }

    // Chip temperature: esp-hal tsens module not available for ESP32-S3.
    // C++ uses Arduino's temperatureRead() which comes from ESP-IDF.
}
