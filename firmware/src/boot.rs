use bt_hci::controller::ExternalController;
use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Stack, StackResources};
use embassy_time::{Duration, Timer};
use esp_hal::{
    i2c::master::I2c,
    rng::Rng,
};
use esp_hal_ota::Ota;
use esp_radio::ble::controller::BleConnector;
use esp_storage::FlashStorage;
use picoserve::AppBuilder;
use static_cell::StaticCell;

use crate::{
    config::{
        self,
        runtime::WifiCredentials,
        topology::{CURRENT_TOPOLOGY, SensorKind},
    },
    filesystems::sd,
    networking, programs, services,
    services::http::{self, HttpAppProps},
    state::{self, DeviceInfo},
};

macro_rules! mk_static {
    ($type:ty, $value:expr) => {{
        static STATIC_CELL: StaticCell<$type> = StaticCell::new();
        STATIC_CELL.uninit().write($value)
    }};
}

pub fn validate_ota_slot() {
    let mut ota = Ota::new(FlashStorage::new()).expect("Cannot create OTA");
    if let Err(error) = ota.ota_mark_app_valid() {
        info!(
            "ota_mark_app_valid failed (may be on factory partition): {:?}",
            error
        );
    } else {
        info!("marked current OTA slot as valid");
    }
}

pub fn initialize_sd_and_filesystem(
    spi: esp_hal::peripherals::SPI2<'static>,
    cs: esp_hal::peripherals::GPIO10<'static>,
    mosi: esp_hal::peripherals::GPIO11<'static>,
    sck: esp_hal::peripherals::GPIO12<'static>,
    miso: esp_hal::peripherals::GPIO13<'static>,
) -> u32 {
    let sd_size_mb = sd::initialize(spi, cs, mosi, sck, miso);
    if let Err(error_message) = sd::ensure_data_csv_exists() {
        info!("failed to initialize data.csv: {}", error_message);
    }
    programs::shell::ensure_filesystem_hierarchy();
    sd_size_mb
}

pub fn initialize_i2c_buses(
    i2c0_peripheral: esp_hal::peripherals::I2C0<'static>,
    i2c1_peripheral: esp_hal::peripherals::I2C1<'static>,
    gpio8: esp_hal::peripherals::GPIO8<'static>,
    gpio9: esp_hal::peripherals::GPIO9<'static>,
    gpio17: esp_hal::peripherals::GPIO17<'static>,
    gpio18: esp_hal::peripherals::GPIO18<'static>,
) -> (
    Option<I2c<'static, esp_hal::Async>>,
    Option<I2c<'static, esp_hal::Async>>,
) {
    let i2c0_bus = CURRENT_TOPOLOGY
        .buses
        .iter()
        .any(|b| b.is_i2c() && b.bus_index == 0)
        .then(|| crate::hardware::i2c::initialize_bus_0(i2c0_peripheral, gpio8, gpio9));

    let i2c1_bus = CURRENT_TOPOLOGY
        .buses
        .iter()
        .any(|b| b.is_i2c() && b.bus_index == 1)
        .then(|| crate::hardware::i2c::initialize_bus_1(i2c1_peripheral, gpio17, gpio18));

    (i2c0_bus, i2c1_bus)
}

pub struct NetworkResources {
    pub stack: Stack<'static>,
    pub ble_controller: ExternalController<BleConnector<'static>, 1>,
}

pub async fn connect_networking(
    spawner: Spawner,
    wifi_peripheral: esp_hal::peripherals::WIFI<'static>,
    bt_peripheral: esp_hal::peripherals::BT<'static>,
    credentials: &WifiCredentials,
) -> NetworkResources {
    let mode_config = networking::build_sta_config(credentials);

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

    let mut random_number_generator = Rng::new();
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

    NetworkResources {
        stack,
        ble_controller,
    }
}

pub async fn wait_for_dhcp(stack: Stack<'static>, sd_size_mb: u32) {
    info!("waiting for STA DHCP configuration...");
    loop {
        if let Some(ip_config) = stack.config_v4() {
            info!("STA connected with IP: {}", ip_config.address);

            state::set_device_info(DeviceInfo {
                ip_address: ip_config.address.address().octets(),
                sd_card_size_mb: sd_size_mb,
            });

            break;
        }

        Timer::after(Duration::from_secs(1)).await;
    }

    loop {
        if stack.is_link_up() {
            info!("network link is up");
            break;
        }

        Timer::after(Duration::from_millis(500)).await;
    }
}

pub fn spawn_sensor_tasks(
    spawner: &Spawner,
    i2c0_bus: &mut Option<I2c<'static, esp_hal::Async>>,
    i2c1_bus: &mut Option<I2c<'static, esp_hal::Async>>,
) {
    for sensor in CURRENT_TOPOLOGY.enabled_sensors() {
        let Some(bus_config) = CURRENT_TOPOLOGY.find_bus(sensor.bus_label) else {
            info!(
                "sensor {}: bus '{}' not found in topology",
                sensor.name, sensor.bus_label
            );
            continue;
        };

        let sensor_requires_explicit_i2c_address =
            !matches!(sensor.kind, SensorKind::Scd30 | SensorKind::Scd4x);

        if !bus_config.is_i2c()
            || (sensor_requires_explicit_i2c_address && sensor.i2c_address.is_none())
        {
            continue;
        }

        let sensor_address = sensor.i2c_address.unwrap_or_default();

        let i2c_bus = match bus_config.bus_index {
            0 => i2c0_bus.take(),
            1 => i2c1_bus.take(),
            _ => None,
        };

        let Some(i2c_bus) = i2c_bus else {
            info!(
                "sensor {}: I2C bus {} not available",
                sensor.name, bus_config.bus_index
            );
            continue;
        };

        match sensor.kind {
            SensorKind::TemperatureAndHumidity => {
                spawner.spawn(
                    programs::temperature_and_humidity::task(
                        i2c_bus,
                        sensor_address,
                        sensor.name,
                    )
                    .unwrap(),
                );
            }
            SensorKind::Scd30 | SensorKind::Scd4x => {
                spawner.spawn(programs::carbon_dioxide::task(i2c_bus).unwrap());
            }
            _ => {
                info!("sensor {}: kind not yet implemented", sensor.name);
            }
        }
    }
}

pub fn start_services(spawner: &Spawner, stack: Stack<'static>) {
    spawner.spawn(networking::sntp::task(stack).unwrap());

    const WEB_TASK_POOL_SIZE: usize = 1;

    let app = mk_static!(
        picoserve::AppRouter<HttpAppProps>,
        HttpAppProps { stack }.build_app()
    );

    for task_id in 0..WEB_TASK_POOL_SIZE {
        spawner.spawn(http::task(task_id, stack, app).unwrap());
    }
    spawner.spawn(services::ota::task(stack).unwrap());
    spawner.spawn(programs::shell::task(stack).unwrap());

    info!("HTTP server listening on port {}", config::http::PORT);
}
