use bt_hci::controller::ExternalController;
use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Stack, StackResources};
use esp_hal::rng::Rng;
use esp_radio::ble::controller::BleConnector;
use static_cell::StaticCell;

use crate::{
    networking,
    networking::wifi::credentials::WifiCredentials,
};

macro_rules! mk_static {
    ($type:ty, $value:expr) => {{
        static STATIC_CELL: StaticCell<$type> = StaticCell::new();
        STATIC_CELL.uninit().write($value)
    }};
}

pub struct NetworkResources {
    pub stack: Stack<'static>,
    pub ble_controller: ExternalController<BleConnector<'static>, 1>,
}

pub async fn initialize_networking(
    spawner: Spawner,
    wifi_peripheral: esp_hal::peripherals::WIFI<'static>,
    bt_peripheral: esp_hal::peripherals::BT<'static>,
    credentials: &WifiCredentials,
) -> NetworkResources {
    let mode_config = networking::wifi::station_config(credentials);

    info!(
        "starting Wi-Fi in STA mode with ssid='{}'",
        credentials.ssid.as_str()
    );

    let ble_connector = BleConnector::new(bt_peripheral, Default::default()).unwrap();
    let ble_controller = ExternalController::<_, 1>::new(ble_connector);

    let (wifi_controller, interfaces) = esp_radio::wifi::new(
        wifi_peripheral,
        esp_radio::wifi::ControllerConfig::default()
            .with_static_rx_buf_num(4)
            .with_dynamic_rx_buf_num(16)
            .with_dynamic_tx_buf_num(16)
            .with_initial_config(mode_config),
    )
    .expect("Failed to initialize Wi-Fi controller");

    info!(
        "attempting STA connection to '{}'",
        credentials.ssid.as_str()
    );

    let random_number_generator = Rng::new();
    let seed = {
        (u64::from(random_number_generator.random()) << 32)
            | u64::from(random_number_generator.random())
    };

    let network_config = embassy_net::Config::dhcpv4(Default::default());
    let (stack, runner) = embassy_net::new(
        interfaces.station,
        network_config,
        mk_static!(StackResources<7>, StackResources::<7>::new()),
        seed,
    );

    spawner.spawn(networking::wifi::sta::connection_task(wifi_controller).unwrap());
    spawner.spawn(networking::wifi::sta::net_task(runner).unwrap());
    spawner.spawn(networking::wifi::sta::lease_monitor_task(stack).unwrap());

    NetworkResources {
        stack,
        ble_controller,
    }
}
