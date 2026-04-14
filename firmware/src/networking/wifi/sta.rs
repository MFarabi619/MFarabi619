//! WiFi station (client) mode — connection task and network runner.

use core::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use defmt::info;
use embassy_net::Stack;
use embassy_net::Runner;
use embassy_time::{Duration, Timer};
use esp_radio::wifi::{Interface, WifiController};

static WIFI_INITIALIZED: AtomicBool = AtomicBool::new(false);
static IPV4_ADDRESS: AtomicU32 = AtomicU32::new(0);

pub struct StaSnapshot {
    pub is_connected: bool,
    pub ipv4_address: [u8; 4],
}

pub fn publish_ipv4_address(ipv4_address: [u8; 4]) {
    IPV4_ADDRESS.store(u32::from_be_bytes(ipv4_address), Ordering::Release);
}

pub fn snapshot() -> StaSnapshot {
    StaSnapshot {
        is_connected: WIFI_INITIALIZED.load(Ordering::Acquire),
        ipv4_address: IPV4_ADDRESS.load(Ordering::Acquire).to_be_bytes(),
    }
}

#[embassy_executor::task]
pub async fn lease_monitor_task(stack: Stack<'static>) {
    let mut last_reported_ipv4 = [0_u8; 4];
    let mut has_reported_link_up = false;

    loop {
        if stack.is_link_up() {
            if !has_reported_link_up {
                info!("network link is up");
                has_reported_link_up = true;
            }

            if let Some(ip_config) = stack.config_v4() {
                let ipv4_address = ip_config.address.address().octets();
                if ipv4_address != last_reported_ipv4 {
                    info!("STA connected with IP: {}", ip_config.address);
                    publish_ipv4_address(ipv4_address);
                    last_reported_ipv4 = ipv4_address;
                }
            }
        } else {
            if has_reported_link_up {
                info!("network link is down");
                has_reported_link_up = false;
            }
            if last_reported_ipv4 != [0_u8; 4] {
                publish_ipv4_address([0_u8; 4]);
                last_reported_ipv4 = [0_u8; 4];
            }
        }

        Timer::after(Duration::from_secs(1)).await;
    }
}

#[embassy_executor::task]
pub async fn connection_task(mut wifi_controller: WifiController<'static>) {
    loop {
        info!("attempting Wi-Fi STA connection");

        match wifi_controller.connect_async().await {
            Ok(_connected_info) => {
                info!("Wi-Fi STA connected");
                WIFI_INITIALIZED.store(true, Ordering::Release);
                let _ = wifi_controller.wait_for_disconnect_async().await;
                WIFI_INITIALIZED.store(false, Ordering::Release);
                IPV4_ADDRESS.store(0, Ordering::Release);
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
