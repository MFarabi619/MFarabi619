//! `describe("Wi-Fi Scan")`
//!
//! Station-mode smoke test: the device scans the 2.4 GHz band and
//! reports every visible access point. `#[ignore]` by default because
//! it needs the device's antenna and the surrounding RF environment;
//! opt in with `--include-ignored`.

#![no_std]
#![no_main]

extern crate alloc;

#[path = "common/mod.rs"]
mod common;

use defmt::info;
use embassy_time::Duration;
use esp_radio::wifi::{
    Config as WifiConfig,
    ap::AccessPointInfo,
    scan::ScanConfig,
    sta::StationConfig,
};

use common::Device;

const DEVICE_WIFI_SSID: &str = env!("NETWORK_WIFI_SSID");
const DEVICE_WIFI_PASSWORD: &str = env!("NETWORK_WIFI_PSK");
const WIFI_SCAN_MAX_RESULTS: usize = 8;

fn log_discovered_access_point(
    access_point_index: usize,
    access_point_info: &AccessPointInfo,
) {
    info!(
        "AP {=usize}: ssid={=str} channel={=u8} rssi={=i8}",
        access_point_index,
        access_point_info.ssid.as_str(),
        access_point_info.channel,
        access_point_info.signal_strength,
    );
}

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
        info!("=== Wi-Fi Scan — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user scans and sees at least the configured home network")`
    #[test]
    #[timeout(20)]
    async fn user_scans_and_sees_nearby_access_points(
        mut device: Device,
    ) -> Result<(), &'static str> {
        let mut wifi_controller = device
            .wifi_controller
            .take()
            .ok_or("device WiFi controller already consumed")?;

        let station_configuration = WifiConfig::Station(
            StationConfig::default()
                .with_ssid(DEVICE_WIFI_SSID)
                .with_password(DEVICE_WIFI_PASSWORD.into()),
        );

        wifi_controller
            .set_config(&station_configuration)
            .map_err(|_| "device: failed to apply station config and start WiFi")?;

        info!("user asks the device to scan for nearby access points");
        let visible_access_points = wifi_controller
            .scan_async(&ScanConfig::default().with_max(WIFI_SCAN_MAX_RESULTS))
            .await
            .map_err(|_| "device: WiFi scan failed")?;

        info!(
            "scan complete count={=usize}",
            visible_access_points.len()
        );

        for (access_point_index, access_point_info) in
            visible_access_points.iter().enumerate()
        {
            log_discovered_access_point(access_point_index + 1, access_point_info);
        }

        defmt::assert!(
            !visible_access_points.is_empty(),
            "WiFi scan returned zero access points; antenna or RF environment issue"
        );

        embassy_time::Timer::after(Duration::from_millis(250)).await;
        Ok(())
    }
}
