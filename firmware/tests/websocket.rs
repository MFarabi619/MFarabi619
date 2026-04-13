#![no_std]
#![no_main]

//! WebSocket protocol contract tests.
//! Validates that DeviceRequest parsing and DeviceEvent serialization
//! produce the expected JSON shapes for the web app to consume.

use defmt::info;
use esp_hal::{interrupt::software::SoftwareInterruptControl, timer::timg::TimerGroup};

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::tests(executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;
    use firmware::services::ws_protocol::{
        DeviceEvent, DeviceRequest, FileEntryPayload, RawRequest,
    };
    use heapless::String as HeaplessString;

    #[init]
    fn init() {
        let peripherals = esp_hal::init(esp_hal::Config::default());
        let timer_group = TimerGroup::new(peripherals.TIMG0);
        let software_interrupts = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
        esp_rtos::start(timer_group.timer0, software_interrupts.software_interrupt0);
        rtt_target::rtt_init_defmt!();
        info!("websocket protocol contract tests initialized");
    }

    // ── Request parsing ─────────────────────────────────────────────────────

    #[test]
    async fn parse_get_status_request() {
        let json = r#"{"action":"get_status"}"#;
        let (raw, _) = serde_json_core::from_str::<RawRequest>(json).unwrap();
        let request = DeviceRequest::from(raw);
        defmt::assert!(matches!(request, DeviceRequest::GetStatus));
    }

    #[test]
    async fn parse_get_co2_request() {
        let json = r#"{"action":"get_co2"}"#;
        let (raw, _) = serde_json_core::from_str::<RawRequest>(json).unwrap();
        let request = DeviceRequest::from(raw);
        defmt::assert!(matches!(request, DeviceRequest::GetCo2));
    }

    #[test]
    async fn parse_scan_wifi_request() {
        let json = r#"{"action":"scan_wifi"}"#;
        let (raw, _) = serde_json_core::from_str::<RawRequest>(json).unwrap();
        let request = DeviceRequest::from(raw);
        defmt::assert!(matches!(request, DeviceRequest::ScanWifi));
    }

    #[test]
    async fn parse_connect_wifi_request() {
        let json = r#"{"action":"connect_wifi","ssid":"openws","password":"secret123"}"#;
        let (raw, _) = serde_json_core::from_str::<RawRequest>(json).unwrap();
        let request = DeviceRequest::from(raw);
        match request {
            DeviceRequest::ConnectWifi { ssid, password } => {
                defmt::assert_eq!(ssid, "openws");
                defmt::assert_eq!(password, "secret123");
            }
            _ => defmt::panic!("expected ConnectWifi"),
        }
    }

    #[test]
    async fn parse_list_files_request() {
        let json = r#"{"action":"list_files","location":"sd"}"#;
        let (raw, _) = serde_json_core::from_str::<RawRequest>(json).unwrap();
        let request = DeviceRequest::from(raw);
        match request {
            DeviceRequest::ListFiles { location } => {
                defmt::assert_eq!(location, "sd");
            }
            _ => defmt::panic!("expected ListFiles"),
        }
    }

    #[test]
    async fn parse_delete_file_request() {
        let json = r#"{"action":"delete_file","location":"sd","path":"DATA.CSV"}"#;
        let (raw, _) = serde_json_core::from_str::<RawRequest>(json).unwrap();
        let request = DeviceRequest::from(raw);
        match request {
            DeviceRequest::DeleteFile { location, path } => {
                defmt::assert_eq!(location, "sd");
                defmt::assert_eq!(path, "DATA.CSV");
            }
            _ => defmt::panic!("expected DeleteFile"),
        }
    }

    #[test]
    async fn parse_unknown_action_returns_unknown() {
        let json = r#"{"action":"do_something_weird"}"#;
        let (raw, _) = serde_json_core::from_str::<RawRequest>(json).unwrap();
        let request = DeviceRequest::from(raw);
        defmt::assert!(matches!(request, DeviceRequest::Unknown));
    }

    // ── Event serialization ─────────────────────────────────────────────────

    #[test]
    async fn serialize_co2_event_contains_type_tag() {
        let event = DeviceEvent::Co2 {
            co2_ppm: 487.0,
            temperature: 23.4,
            humidity: 41.2,
            model: "SCD30",
            ok: true,
        };
        let mut buffer = [0u8; 256];
        let json = serde_json_core::to_string::<_, 256>(&event).unwrap();
        info!("co2 event: {}", json.as_str());
        defmt::assert!(json.contains("\"type\":\"co2\""));
        defmt::assert!(json.contains("\"co2_ppm\":"));
        defmt::assert!(json.contains("\"temperature\":"));
        defmt::assert!(json.contains("\"humidity\":"));
        defmt::assert!(json.contains("\"model\":\"SCD30\""));
        defmt::assert!(json.contains("\"ok\":true"));
    }

    #[test]
    async fn serialize_status_event_contains_type_tag() {
        let event = DeviceEvent::Status {
            hostname: "ceratina",
            platform: "esp32s3",
            uptime_seconds: 3600,
            heap_free: 65000,
            heap_used: 7000,
            sd_card_mb: 1790,
        };
        let json = serde_json_core::to_string::<_, 256>(&event).unwrap();
        info!("status event: {}", json.as_str());
        defmt::assert!(json.contains("\"type\":\"status\""));
        defmt::assert!(json.contains("\"hostname\":\"ceratina\""));
        defmt::assert!(json.contains("\"uptime_seconds\":3600"));
    }

    #[test]
    async fn serialize_error_event_contains_type_tag() {
        let event = DeviceEvent::Error {
            message: "wifi scan not yet implemented",
        };
        let json = serde_json_core::to_string::<_, 256>(&event).unwrap();
        info!("error event: {}", json.as_str());
        defmt::assert!(json.contains("\"type\":\"error\""));
        defmt::assert!(json.contains("\"message\":\"wifi scan not yet implemented\""));
    }

    #[test]
    async fn serialize_file_list_event_contains_entries() {
        let files = [
            FileEntryPayload {
                name: {
                    let mut name = HeaplessString::<32>::new();
                    let _ = core::fmt::Write::write_str(&mut name, "DATA.CSV");
                    name
                },
                size: 205,
            },
        ];
        let event = DeviceEvent::FileList {
            location: "sd",
            files: &files,
        };
        let json = serde_json_core::to_string::<_, 256>(&event).unwrap();
        info!("file_list event: {}", json.as_str());
        defmt::assert!(json.contains("\"type\":\"file_list\""));
        defmt::assert!(json.contains("\"location\":\"sd\""));
        defmt::assert!(json.contains("\"name\":\"DATA.CSV\""));
        defmt::assert!(json.contains("\"size\":205"));
    }
}
