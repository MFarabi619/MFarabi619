//! WiFi station (client) mode — connection task and network runner.

use defmt::info;
use embassy_net::Runner;
use embassy_time::{Duration, Timer};
use esp_radio::wifi::{Interface, WifiController};

use crate::state;

#[embassy_executor::task]
pub async fn connection_task(mut wifi_controller: WifiController<'static>) {
    loop {
        info!("attempting Wi-Fi STA connection");

        match wifi_controller.connect_async().await {
            Ok(_connected_info) => {
                info!("Wi-Fi STA connected");
                state::WIFI_INITIALIZED.store(true, core::sync::atomic::Ordering::Release);
                let _ = wifi_controller.wait_for_disconnect_async().await;
                state::WIFI_INITIALIZED.store(false, core::sync::atomic::Ordering::Release);
                info!("Wi-Fi STA disconnected");
            }
            Err(error) => {
                info!("Wi-Fi STA connect failed: {:?}", error);
                Timer::after(Duration::from_secs(5)).await;
            }
        }
    }
}

#[embassy_executor::task]
pub async fn net_task(mut runner: Runner<'static, Interface<'static>>) {
    runner.run().await;
}
