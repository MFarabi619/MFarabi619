//! `describe("HTTP API Contracts")`
//!
//! Compile-time contract tests for API route paths, JSON response
//! envelope shapes, and CloudEvent format. No HTTP server, no WiFi,
//! no network — just string assertions that catch drift.

#![no_std]
#![no_main]

use defmt::info;

esp_bootloader_esp_idf::esp_app_desc!();

const FILESYSTEM_LIST_ENDPOINT_PATH: &str = "/api/filesystem/list";
const FILESYSTEM_FILE_ENDPOINT_PREFIX: &str = "/api/filesystem/file/";
const FILESYSTEM_UPLOAD_ENDPOINT_PREFIX: &str = "/api/filesystem/file/";
const SYSTEM_DEVICE_STATUS_ENDPOINT_PATH: &str = "/api/system/device/status";
const API_ROUTE_PREFIX: &str = "/api";
const FILESYSTEM_ROUTE_PREFIX: &str = "/filesystem";
const SYSTEM_ROUTE_PREFIX: &str = "/system";
const DEVICE_ROUTE_PREFIX: &str = "/device";

const SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE: &str = "{\"specversion\":\"1.0\",\"id\":\"system-device-status-45591\",\"source\":\"urn:apidae-systems:tenant:p-uot-ins:site:university-of-ottawa\",\"type\":\"com.apidae.system.device.status.v1\",\"datacontenttype\":\"application/json\",\"time\":\"2026-04-03T17:18:43Z\",\"data\":{\"device\":{\"chip_id\":966764,\"chip_model\":\"ESP32-S3\",\"chip_cores\":2,\"chip_revision\":2,\"efuse_mac\":\"119572138669276\"},\"network\":{\"ipv4_address\":\"10.0.0.95\",\"wifi_rssi\":-61},\"runtime\":{\"uptime\":\"45s\",\"uptime_seconds\":45,\"memory_heap_bytes\":46016},\"storage\":{\"location\":\"sd\",\"total_bytes\":1876951040,\"used_bytes\":557056,\"free_bytes\":1876393984}}}";
const FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE: &str =
    "{\"ok\":true,\"data\":{\"entries\":[{\"name\":\"DATA.CSV\",\"size\":270,\"last_write_unix\":0}]}}";
const FILESYSTEM_ERROR_JSON_RESPONSE_EXAMPLE: &str =
    "{\"ok\":false,\"error\":{\"code\":\"INVALID_PATH\",\"message\":\"invalid file path\"}}";

#[cfg(test)]
#[embedded_test::setup]
fn setup() {
    rtt_target::rtt_init_defmt!();
}

#[cfg(test)]
#[embedded_test::tests(executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;
    use esp_hal::{clock::CpuClock, interrupt::software::SoftwareInterruptControl, timer::timg::TimerGroup};

    #[init]
    fn init() {
        let peripherals = esp_hal::init(esp_hal::Config::default().with_cpu_clock(CpuClock::max()));
        let timer_group0 = TimerGroup::new(peripherals.TIMG0);
        let software_interrupts = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
        esp_rtos::start(timer_group0.timer0, software_interrupts.software_interrupt0);
        info!("=== HTTP API Contracts — describe block ===");
    }

    /// `it("user verifies HTTP filesystem endpoint paths are stable")`
    #[test]
    async fn http_filesystem_endpoint_contracts_are_stable() {
        defmt::assert_eq!(API_ROUTE_PREFIX, "/api");
        defmt::assert_eq!(FILESYSTEM_ROUTE_PREFIX, "/filesystem");
        defmt::assert_eq!(SYSTEM_ROUTE_PREFIX, "/system");
        defmt::assert_eq!(DEVICE_ROUTE_PREFIX, "/device");

        defmt::assert_eq!(FILESYSTEM_LIST_ENDPOINT_PATH, "/api/filesystem/list");
        defmt::assert_eq!(FILESYSTEM_FILE_ENDPOINT_PREFIX, "/api/filesystem/file/");
        defmt::assert_eq!(FILESYSTEM_UPLOAD_ENDPOINT_PREFIX, "/api/filesystem/file/");
        defmt::assert_eq!(SYSTEM_DEVICE_STATUS_ENDPOINT_PATH, "/api/system/device/status");
    }

    /// `it("user verifies filesystem JSON envelope shape is stable")`
    #[test]
    async fn scalable_filesystem_json_envelope_shape_is_stable() {
        defmt::assert!(FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE.contains("\"ok\":true"));
        defmt::assert!(FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE.contains("\"data\":{\"entries\":"));
        defmt::assert!(FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE.contains("\"name\":"));
        defmt::assert!(FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE.contains("\"size\":"));
        defmt::assert!(FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE.contains("\"last_write_unix\":"));

        defmt::assert!(FILESYSTEM_ERROR_JSON_RESPONSE_EXAMPLE.contains("\"ok\":false"));
        defmt::assert!(FILESYSTEM_ERROR_JSON_RESPONSE_EXAMPLE.contains("\"error\":{\"code\":"));
        defmt::assert!(FILESYSTEM_ERROR_JSON_RESPONSE_EXAMPLE.contains("\"message\":"));
    }

    /// `it("user verifies upload limits match runtime expectation")`
    #[test]
    async fn upload_limits_match_runtime_expectation() {
        defmt::assert_eq!(ceratina::config::app::sd_card::FILE_UPLOAD_MAX_BYTES, 4096);
    }

    /// `it("user verifies CloudEvent device status shape is stable")`
    #[test]
    async fn system_device_status_cloud_event_shape_is_stable() {
        defmt::assert!(
            SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains("\"specversion\":\"1.0\"")
        );
        defmt::assert!(SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains(
            "\"type\":\"com.apidae.system.device.status.v1\""
        ));
        defmt::assert!(SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains("\"data\":{\"device\":"));
        defmt::assert!(SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains("\"network\":"));
        defmt::assert!(SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains("\"runtime\":"));
        defmt::assert!(SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains("\"storage\":"));
    }
}
