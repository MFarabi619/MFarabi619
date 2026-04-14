//! `describe("WiFi")`
//!
//! WiFi station-mode tests: scan for access points and join the
//! configured home network via DHCP. Merged from wifi_scan.rs and
//! wifi_dhcp.rs.

#![no_std]
#![no_main]

extern crate alloc;

#[path = "common/mod.rs"]
mod common;

use defmt::info;
use embassy_time::Duration;
use esp_radio::wifi::{
    Config as WifiConfig,
    scan::ScanConfig,
    sta::StationConfig,
};

use common::{Device, tasks};

const WIFI_SSID: &str = env!("WIFI_SSID");
const WIFI_PSK: &str = env!("WIFI_PSK");
const SCAN_MAX_RESULTS: usize = 8;

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
        info!("=== WiFi — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user scans and sees nearby access points")`
    #[test]
    #[timeout(20)]
    async fn user_scans_and_sees_nearby_access_points(
        mut device: Device,
    ) -> Result<(), &'static str> {
        let mut wifi_controller = device
            .wifi_controller
            .take()
            .ok_or("device WiFi controller already consumed")?;

        let station_config = WifiConfig::Station(
            StationConfig::default()
                .with_ssid(WIFI_SSID)
                .with_password(WIFI_PSK.into()),
        );

        wifi_controller
            .set_config(&station_config)
            .map_err(|_| "device: failed to apply station config")?;

        info!("user asks the device to scan for nearby access points");
        let visible = wifi_controller
            .scan_async(&ScanConfig::default().with_max(SCAN_MAX_RESULTS))
            .await
            .map_err(|_| "device: WiFi scan failed")?;

        info!("scan complete count={=usize}", visible.len());
        for (i, ap) in visible.iter().enumerate() {
            info!(
                "AP {=usize}: ssid={=str} channel={=u8} rssi={=i8}",
                i + 1,
                ap.ssid.as_str(),
                ap.channel,
                ap.signal_strength,
            );
        }

        defmt::assert!(!visible.is_empty(), "WiFi scan returned zero access points");

        embassy_time::Timer::after(Duration::from_millis(250)).await;
        device.wifi_controller = Some(wifi_controller);
        Ok(())
    }

    /// `it("user joins home WiFi and receives a DHCP lease")`
    #[test]
    #[timeout(30)]
    async fn user_joins_home_wifi_and_receives_dhcp_lease(
        mut device: Device,
    ) -> Result<(), &'static str> {
        let embassy_spawner =
            unsafe { embassy_executor::Spawner::for_current_executor() }.await;

        tasks::wifi::connect_to_home_access_point(&mut device, embassy_spawner).await?;

        let stack = device
            .embassy_network_stack
            .ok_or("device: embassy-net stack missing after DHCP")?;
        let ipv4 = stack
            .config_v4()
            .ok_or("device: DHCP completed but no IPv4 config")?;

        info!(
            "DHCP address acquired ipv4={=[u8]:?}",
            ipv4.address.address().octets()
        );
        Ok(())
    }

    /// `it("user observes default credentials match env vars")`
    #[test]
    async fn user_observes_default_credentials_match_env_vars(
        _device: Device,
    ) -> Result<(), &'static str> {
        use firmware::networking::wifi::credentials;

        let defaults = credentials::default_credentials();

        info!(
            "default ssid={=str} password_len={=usize}",
            defaults.ssid.as_str(),
            defaults.password.len()
        );

        defmt::assert_eq!(defaults.ssid.as_str(), WIFI_SSID);
        defmt::assert_eq!(defaults.password.as_str(), WIFI_PSK);
        defmt::assert!(!defaults.ssid.is_empty(), "default SSID is empty");
        Ok(())
    }

    /// `it("user writes and reads WiFi credentials from flash")`
    #[test]
    async fn user_writes_and_reads_wifi_credentials_from_flash(
        _device: Device,
    ) -> Result<(), &'static str> {
        use firmware::networking::wifi::credentials;

        let mut flash = esp_storage::FlashStorage::new();

        // Save whatever is currently in flash so we can restore it
        let original = credentials::read_from_flash(&mut flash);

        // Write test credentials
        let wrote = credentials::write_to_flash(&mut flash, "test-ssid", "test-pass");
        defmt::assert!(wrote, "write_to_flash failed");

        // Read back and verify
        let readback = credentials::read_from_flash(&mut flash)
            .ok_or("read_from_flash returned None after write")?;

        defmt::assert_eq!(readback.ssid.as_str(), "test-ssid");
        defmt::assert_eq!(readback.password.as_str(), "test-pass");

        info!("credential flash roundtrip verified");

        // Restore original credentials
        if let Some(orig) = original {
            credentials::write_to_flash(&mut flash, orig.ssid.as_str(), orig.password.as_str());
        }

        Ok(())
    }

    /// `it("user observes read_from_flash returns None when no credentials stored")`
    #[test]
    async fn user_observes_read_returns_none_without_credentials(
        _device: Device,
    ) -> Result<(), &'static str> {
        use embedded_storage::nor_flash::NorFlash;
        use firmware::networking::wifi::credentials;

        let mut flash = esp_storage::FlashStorage::new();

        // Save original
        let original = credentials::read_from_flash(&mut flash);

        // Erase the credential sector
        NorFlash::erase(&mut flash, 0x1000, 0x2000)
            .map_err(|_| "flash erase failed")?;

        // Read should return None
        let result = credentials::read_from_flash(&mut flash);
        defmt::assert!(result.is_none(), "expected None after erasing credentials");

        info!("read_from_flash returns None when flash is erased");

        // Restore original credentials
        if let Some(orig) = original {
            credentials::write_to_flash(&mut flash, orig.ssid.as_str(), orig.password.as_str());
        }

        Ok(())
    }
}
