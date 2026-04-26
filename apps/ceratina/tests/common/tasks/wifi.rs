//! WiFi tasks — start an access point, wait for a station to join,
//! connect the device to an existing access point in station mode.

use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Runner, Stack, StackResources};
use embassy_time::{Duration, with_timeout};
use esp_radio::wifi::{
    AccessPointStationEventInfo, Config as WifiConfig, Interface,
    ap::AccessPointConfig,
    sta::StationConfig,
};
use static_cell::StaticCell;

use crate::common::setup::{Device, build_access_point_stack, run_embassy_network};

pub const DEFAULT_STATION_SSID: &str = env!("WIFI_SSID");
pub const DEFAULT_STATION_PASSWORD: &str = env!("WIFI_PSK");

pub const DEFAULT_ACCESS_POINT_SSID: &str = "ceratina-test-ap";
pub const DEFAULT_ACCESS_POINT_PASSWORD: &str = "ceratina123";
pub const DEFAULT_ACCESS_POINT_CHANNEL: u8 = 6;

pub async fn start_access_point(
    device: &mut Device,
    embassy_spawner: Spawner,
) -> Result<(), &'static str> {
    info!(
        "user starts the device access point ssid={=str} channel={=u8}",
        DEFAULT_ACCESS_POINT_SSID, DEFAULT_ACCESS_POINT_CHANNEL
    );

    if device.embassy_network_stack.is_some() {
        return Ok(());
    }

    let mut wifi_controller = device
        .wifi_controller
        .take()
        .ok_or("device WiFi controller already consumed")?;
    let wifi_interfaces = device
        .wifi_interfaces
        .take()
        .ok_or("device WiFi interfaces already consumed")?;

    let access_point_configuration = WifiConfig::AccessPoint(
        AccessPointConfig::default()
            .with_ssid(DEFAULT_ACCESS_POINT_SSID)
            .with_password(DEFAULT_ACCESS_POINT_PASSWORD.into())
            .with_channel(DEFAULT_ACCESS_POINT_CHANNEL),
    );

    wifi_controller
        .set_config(&access_point_configuration)
        .map_err(|_| "device: failed to apply AP config and start WiFi")?;

    let (embassy_network_stack, embassy_network_runner) = build_access_point_stack(
        wifi_interfaces.access_point,
        device.embassy_network_seed,
    );

    embassy_spawner.spawn(
        run_embassy_network(embassy_network_runner)
            .map_err(|_| "device: failed to allocate network runner task")?,
    );

    embassy_network_stack.wait_config_up().await;

    info!("device access point is up at 192.168.4.1");

    device.wifi_controller = Some(wifi_controller);
    device.embassy_network_stack = Some(embassy_network_stack);

    Ok(())
}

pub async fn wait_for_first_station(device: &mut Device) -> Result<(), &'static str> {
    info!(
        "user is expected to connect ssid={=str} password={=str}",
        DEFAULT_ACCESS_POINT_SSID, DEFAULT_ACCESS_POINT_PASSWORD
    );

    let wifi_controller = device
        .wifi_controller
        .as_ref()
        .ok_or("device WiFi controller not initialised — call start_access_point first")?;

    loop {
        match wifi_controller.wait_for_access_point_connected_event_async().await {
            Ok(AccessPointStationEventInfo::Connected(connected_info)) => {
                info!(
                    "user successfully connected to the device access point mac={=[u8]:#x} aid={=u16}",
                    connected_info.mac, connected_info.aid
                );
                return Ok(());
            }
            Ok(AccessPointStationEventInfo::Disconnected(_disconnected_info)) => continue,
            Err(_wifi_error) => {
                return Err("device: error waiting for AP-station-connected event");
            }
        }
    }
}

#[embassy_executor::task]
async fn station_connection_loop(mut wifi_controller: esp_radio::wifi::WifiController<'static>) {
    loop {
        match wifi_controller.connect_async().await {
            Ok(_connected_station_info) => {
                info!("device station connected");
                let _ = wifi_controller.wait_for_disconnect_async().await;
                info!("device station disconnected");
            }
            Err(_wifi_error) => {
                embassy_time::Timer::after(Duration::from_secs(2)).await;
            }
        }
    }
}

fn build_station_network_stack(
    station_interface: Interface<'static>,
    embassy_network_seed: u64,
) -> (Stack<'static>, Runner<'static, Interface<'static>>) {
    let dhcp_network_config = embassy_net::Config::dhcpv4(Default::default());

    static STATION_STACK_RESOURCES: StaticCell<StackResources<3>> = StaticCell::new();
    let stack_resources = STATION_STACK_RESOURCES.init(StackResources::<3>::new());

    embassy_net::new(
        station_interface,
        dhcp_network_config,
        stack_resources,
        embassy_network_seed,
    )
}

pub async fn connect_to_home_access_point(
    device: &mut Device,
    embassy_spawner: Spawner,
) -> Result<(), &'static str> {
    info!(
        "user connects the device to home WiFi ssid={=str}",
        DEFAULT_STATION_SSID
    );

    if device.embassy_network_stack.is_some() {
        return Ok(());
    }

    let mut wifi_controller = device
        .wifi_controller
        .take()
        .ok_or("device WiFi controller already consumed")?;
    let wifi_interfaces = device
        .wifi_interfaces
        .take()
        .ok_or("device WiFi interfaces already consumed")?;

    let station_configuration = WifiConfig::Station(
        StationConfig::default()
            .with_ssid(DEFAULT_STATION_SSID)
            .with_password(DEFAULT_STATION_PASSWORD.into()),
    );

    wifi_controller
        .set_config(&station_configuration)
        .map_err(|_| "device: failed to apply station config and start WiFi")?;

    let (embassy_network_stack, embassy_network_runner) = build_station_network_stack(
        wifi_interfaces.station,
        device.embassy_network_seed,
    );

    embassy_spawner.spawn(
        run_embassy_network(embassy_network_runner)
            .map_err(|_| "device: failed to spawn network runner task")?,
    );
    embassy_spawner.spawn(
        station_connection_loop(wifi_controller)
            .map_err(|_| "device: failed to spawn station connection task")?,
    );

    with_timeout(Duration::from_secs(25), embassy_network_stack.wait_config_up())
        .await
        .map_err(|_| "device: DHCP did not complete within 25 seconds")?;

    let ipv4_config = embassy_network_stack
        .config_v4()
        .ok_or("device: station stack has no IPv4 config after DHCP")?;
    info!(
        "device station has ipv4={=[u8]:?}",
        ipv4_config.address.address().octets()
    );

    device.embassy_network_stack = Some(embassy_network_stack);
    Ok(())
}
