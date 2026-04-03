#![no_std]
#![no_main]

extern crate alloc;

use defmt::info;
use embassy_time::Duration;
use esp_hal::{clock::CpuClock, peripherals::WIFI, timer::timg::TimerGroup};
use esp_radio::wifi::{AccessPointInfo, ClientConfig, ModeConfig, ScanConfig};

const WIFI_SSID: &str = env!("NETWORK_WIFI_SSID");
const WIFI_PASSWORD: &str = env!("NETWORK_WIFI_PSK");
const WIFI_SCAN_LIMIT: usize = 8;

struct Context {
    radio_controller: esp_radio::Controller<'static>,
    wifi: WIFI<'static>,
}

fn client_mode_config() -> ModeConfig {
    ModeConfig::Client(
        ClientConfig::default()
            .with_ssid(WIFI_SSID.into())
            .with_password(WIFI_PASSWORD.into()),
    )
}

fn log_access_point(access_point_index: usize, access_point_info: &AccessPointInfo) {
    info!(
        "AP {}: ssid='{}' channel={} rssi={} auth={:?}",
        access_point_index,
        access_point_info.ssid.as_str(),
        access_point_info.channel,
        access_point_info.signal_strength,
        access_point_info.auth_method
    );
}

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::tests(default_timeout = 30, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Context {
        let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
        let peripherals = esp_hal::init(config);

        esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 64 * 1024);
        esp_alloc::heap_allocator!(size: 64 * 1024);

        let timer_group0 = TimerGroup::new(peripherals.TIMG0);
        esp_rtos::start(timer_group0.timer0);

        rtt_target::rtt_init_defmt!();

        let radio_controller = esp_radio::init().unwrap();

        info!("Wi-Fi scan test initialized");

        Context {
            radio_controller,
            wifi: peripherals.WIFI,
        }
    }

    #[test]
    #[timeout(20)]
    async fn scan_for_access_points(context: Context) {
        let (mut wifi_controller, _interfaces) =
            esp_radio::wifi::new(&context.radio_controller, context.wifi, Default::default())
                .unwrap();

        let mode_config = client_mode_config();
        wifi_controller.set_config(&mode_config).unwrap();
        wifi_controller.start_async().await.unwrap();

        info!("starting Wi-Fi scan");
        let access_points = wifi_controller
            .scan_with_config_async(ScanConfig::default().with_max(WIFI_SCAN_LIMIT))
            .await
            .unwrap();

        info!("scan complete: {} access point(s)", access_points.len());

        for (access_point_index, access_point_info) in access_points.iter().enumerate() {
            log_access_point(access_point_index + 1, access_point_info);
        }

        embassy_time::Timer::after(Duration::from_millis(250)).await;
    }
}
