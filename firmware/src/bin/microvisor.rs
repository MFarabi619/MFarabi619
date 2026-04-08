#![no_std]
#![no_main]
#![feature(impl_trait_in_assoc_type)]
#![deny(
    clippy::mem_forget,
    reason = "mem::forget is generally not safe to do with esp_hal types, especially those \
    holding buffers for the duration of a data transfer."
)]
#![deny(clippy::large_stack_frames)]

extern crate alloc;

use bt_hci::controller::ExternalController;
use defmt::info;
use embassy_executor::Spawner;
use embassy_net::StackResources;
use embassy_time::{Duration, Instant, Timer};
use esp_hal::{
    clock::CpuClock,
    delay::Delay,
    gpio::{Level, Output, OutputConfig},
    i2c::master::{Config as I2cConfig, I2c},
    interrupt::software::SoftwareInterruptControl,
    rng::Rng,
    time::Rate,
    timer::timg::TimerGroup,
};
use esp_hal_ota::Ota;
use esp_radio::ble::controller::BleConnector;
use esp_storage::FlashStorage;
use heapless::String as HeaplessString;
use panic_rtt_target as _;
use picoserve::AppBuilder;
use static_cell::StaticCell;
use trouble_host::prelude::*;

use firmware::{
    config::{self, runtime::WifiCredentials, topology::{CURRENT_TOPOLOGY, SensorKind}},
    filesystems::sd,
    state::{self, AppState},
    networking, programs, services,
    services::http::{self, HTTP_SERVER_PORT, HttpAppProps},
};

esp_bootloader_esp_idf::esp_app_desc!();

macro_rules! mk_static {
    ($type:ty, $value:expr) => {{
        static STATIC_CELL: StaticCell<$type> = StaticCell::new();
        STATIC_CELL.uninit().write($value)
    }};
}

fn random_seed(random_number_generator: &mut Rng) -> u64 {
    (u64::from(random_number_generator.random()) << 32)
        | u64::from(random_number_generator.random())
}

#[allow(
    clippy::large_stack_frames,
    reason = "it's not unusual to allocate larger buffers etc. in main"
)]
#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 73744);
    esp_alloc::heap_allocator!(size: 64 * 1024);
    esp_alloc::psram_allocator!(peripherals.PSRAM, esp_hal::psram);

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    let sw_ints = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
    esp_rtos::start(timg0.timer0, sw_ints.software_interrupt0);

    info!("Embassy initialized!");
    info!("host_platform={}", config::PLATFORM);
    info!("active_user_key={}", config::ACTIVE_USER_KEY);
    info!("time_zone={}", config::time::ZONE);
    info!(
        "filesystem.sd_card: device={} fs_type={} data_log_path={}",
        config::sd_card::DEVICE,
        config::sd_card::FS_TYPE,
        config::sd_card::DATA_LOG_PATH
    );
    info!(
        "networking.ap_fallback={} ap_ssid={} ap_channel={} ap_max_connections={} ap_auth_mode={}",
        config::wifi::FALLBACK_TO_AP,
        config::wifi::ap::SSID,
        config::wifi::ap::CHANNEL,
        config::wifi::ap::MAX_CONNECTIONS,
        config::wifi::ap::AUTH_MODE,
    );

    {
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

    let _sensor_power_relay = match config::SENSOR_POWER_GPIO {
        5 => Output::new(peripherals.GPIO5, Level::High, OutputConfig::default()),
        unsupported_gpio => {
            panic!("unsupported sensor_power_enable_gpio={}", unsupported_gpio)
        }
    };
    Delay::new().delay_millis(1_000);

    let sd_size_mb = sd::initialize(
        peripherals.SPI2,
        peripherals.GPIO10,
        peripherals.GPIO11,
        peripherals.GPIO12,
        peripherals.GPIO13,
    );
    if let Err(error_message) = sd::ensure_data_csv_exists() {
        info!("failed to initialize data.csv: {}", error_message);
    }
    programs::shell::ensure_filesystem_hierarchy();

    // Initialize I2C buses from hardware topology configuration.
    // Each bus is initialized directly because GPIO pins are different concrete types.
    let mut i2c0_bus: Option<I2c<'static, esp_hal::Async>> = CURRENT_TOPOLOGY
        .buses
        .iter()
        .find(|b| b.is_i2c() && b.bus_index == 0)
        .and_then(|bus_config| {
            let (sda_pin, scl_pin) = bus_config.i2c_pins()?;
            // Pins are known at compile time from config — match to concrete types.
            let bus = match (sda_pin, scl_pin) {
                (8, 9) => I2c::new(
                    peripherals.I2C0,
                    I2cConfig::default()
                        .with_frequency(Rate::from_khz(config::I2C_FREQUENCY_KHZ)),
                )
                .unwrap()
                .with_sda(peripherals.GPIO8)
                .with_scl(peripherals.GPIO9)
                .into_async(),
                (15, 16) => I2c::new(
                    peripherals.I2C0,
                    I2cConfig::default()
                        .with_frequency(Rate::from_khz(config::I2C_FREQUENCY_KHZ)),
                )
                .unwrap()
                .with_sda(peripherals.GPIO15)
                .with_scl(peripherals.GPIO16)
                .into_async(),
                _ => return None,
            };
            Some(bus)
        });

    let mut i2c1_bus: Option<I2c<'static, esp_hal::Async>> = CURRENT_TOPOLOGY
        .buses
        .iter()
        .find(|b| b.is_i2c() && b.bus_index == 1)
        .and_then(|bus_config| {
            let (sda_pin, scl_pin) = bus_config.i2c_pins()?;
            let bus = match (sda_pin, scl_pin) {
                (17, 18) => I2c::new(
                    peripherals.I2C1,
                    I2cConfig::default()
                        .with_frequency(Rate::from_khz(config::I2C_FREQUENCY_KHZ)),
                )
                .unwrap()
                .with_sda(peripherals.GPIO17)
                .with_scl(peripherals.GPIO18)
                .into_async(),
                _ => return None,
            };
            Some(bus)
        });

    state::set_app_state(AppState {
        cloud_event_source: config::CLOUD_EVENTS_SOURCE,
        cloud_event_type: config::CLOUD_EVENT_TYPE,
        boot_timestamp_seconds: Instant::now().as_secs(),
    });

    let mut flash = FlashStorage::new();
    let credentials = config::runtime::read_credentials(&mut flash).unwrap_or_else(|| {
        info!("no credentials in flash, using defaults");
        WifiCredentials {
            ssid: HeaplessString::try_from(config::runtime::DEFAULT_SSID).unwrap(),
            password: HeaplessString::try_from(config::runtime::DEFAULT_PASSWORD).unwrap(),
        }
    });

    let mode_config = networking::build_sta_config(&credentials);

    info!(
        "starting Wi-Fi in STA mode with ssid='{}'",
        credentials.ssid.as_str()
    );
    let (wifi_controller, interfaces) = esp_radio::wifi::new(
        peripherals.WIFI,
        esp_radio::wifi::ControllerConfig::default().with_initial_config(mode_config),
    )
    .expect("Failed to initialize Wi-Fi controller");

    info!("attempting STA connection to '{}'", credentials.ssid.as_str());

    let mut random_number_generator = Rng::new();
    let seed = random_seed(&mut random_number_generator);

    let network_config = embassy_net::Config::dhcpv4(Default::default());
    let (stack, runner) = embassy_net::new(
        interfaces.station,
        network_config,
        mk_static!(StackResources<7>, StackResources::<7>::new()),
        seed,
    );

    spawner.spawn(networking::wifi::sta::connection_task(wifi_controller).unwrap());
    spawner.spawn(networking::wifi::sta::net_task(runner).unwrap());

    // Spawn sensor tasks based on hardware topology configuration.
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

        // TODO: Add mux channel selection when sensor.uses_mux() is true.
        // Currently all sensors have mux_channel: None (direct connection).
        // When a sensor needs a mux, select the channel before I2C transactions.

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

    info!("waiting for STA DHCP configuration...");
    loop {
        if let Some(ip_config) = stack.config_v4() {
            info!("STA connected with IP: {}", ip_config.address);

            state::set_device_info(state::DeviceInfo {
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

    info!("HTTP server listening on port {}", HTTP_SERVER_PORT);

    let transport = BleConnector::new(peripherals.BT, Default::default()).unwrap();
    let ble_controller = ExternalController::<_, 1>::new(transport);
    let mut resources: HostResources<DefaultPacketPool, 1, 1> = HostResources::new();
    let _ble_stack = trouble_host::new(ble_controller, &mut resources);

    loop {
        Timer::after(Duration::from_secs(60)).await;
    }
}
