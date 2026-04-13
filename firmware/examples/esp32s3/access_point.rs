#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Ipv4Cidr, Runner, Stack, StackResources, StaticConfigV4};
use embassy_time::{Duration, Timer};
use esp_hal::{
    clock::CpuClock,
    interrupt::software::SoftwareInterruptControl,
    rng::Rng,
    timer::timg::TimerGroup,
};
use esp_radio::wifi::{Config, ControllerConfig, Interface, WifiController, ap::AccessPointConfig};
use panic_rtt_target as _;
use picoserve::routing::get;
use static_cell::StaticCell;

use firmware::config;

const AP_SSID: &str = env!("NETWORK_WIFI_SSID");
const AP_PASSWORD: &str = env!("NETWORK_WIFI_PSK");
const AP_CHANNEL: u8 = 6;

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

#[embassy_executor::task]
async fn wifi_ap_task(wifi_controller: WifiController<'static>) {
    let _ = wifi_controller;
    loop {
        Timer::after(Duration::from_secs(60)).await;
    }
}

#[embassy_executor::task]
async fn wifi_net_task(mut runner: Runner<'static, Interface<'static>>) {
    runner.run().await;
}

#[embassy_executor::task]
async fn http_server_task(stack: Stack<'static>) {
    let app = picoserve::Router::new().route(
        "/",
        get(|| async {
            (
                ("Content-Type", "text/html; charset=utf-8"),
                concat!(
                    "<!DOCTYPE html><html><head><title>Ceratina Setup</title></head><body>",
                    "<h1>Ceratina Device Setup</h1>",
                    "<p>Connect this device to your Wi-Fi network.</p>",
                    "</body></html>",
                ),
            )
        }),
    );

    let config = mk_static!(
        picoserve::Config,
        picoserve::Config::new(picoserve::Timeouts {
            start_read_request: Duration::from_secs(5),
            persistent_start_read_request: Duration::from_secs(5),
            read_request: Duration::from_secs(2),
            write: Duration::from_secs(2),
        })
        .keep_connection_alive()
    );

    let mut tcp_rx_buffer = [0u8; 2048];
    let mut tcp_tx_buffer = [0u8; 2048];
    let mut http_buffer = [0u8; 4096];

    loop {
        picoserve::Server::new(&app, config, &mut http_buffer)
            .listen_and_serve(0usize, stack, config::http::PORT, &mut tcp_rx_buffer, &mut tcp_tx_buffer)
            .await;
    }
}

#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 73744);
    esp_alloc::heap_allocator!(size: 64 * 1024);

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    let sw_ints = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
    esp_rtos::start(timg0.timer0, sw_ints.software_interrupt0);

    info!("Embassy initialized!");

    let ap_config = Config::AccessPoint(
        AccessPointConfig::default()
            .with_ssid(AP_SSID)
            .with_password(AP_PASSWORD.into())
            .with_channel(AP_CHANNEL),
    );

    info!("starting Wi-Fi in AP mode");
    let (wifi_controller, interfaces) = esp_radio::wifi::new(
        peripherals.WIFI,
        ControllerConfig::default().with_initial_config(ap_config),
    )
    .expect("Failed to initialize Wi-Fi controller");

    info!("AP '{}' started on channel {}", AP_SSID, AP_CHANNEL);
    info!("AP IP: 192.168.4.1");

    let mut random_number_generator = Rng::new();
    let seed = random_seed(&mut random_number_generator);

    let ap_network_config = embassy_net::Config::ipv4_static(StaticConfigV4 {
        address: Ipv4Cidr::new(
            core::net::Ipv4Addr::new(192, 168, 4, 1),
            24,
        ),
        gateway: Some(core::net::Ipv4Addr::new(192, 168, 4, 1)),
        dns_servers: Default::default(),
    });

    let (stack, runner) = embassy_net::new(
        interfaces.access_point,
        ap_network_config,
        mk_static!(StackResources<3>, StackResources::<3>::new()),
        seed,
    );

    spawner.spawn(wifi_ap_task(wifi_controller).unwrap());
    spawner.spawn(wifi_net_task(runner).unwrap());

    stack.wait_config_up().await;

    spawner.spawn(http_server_task(stack).unwrap());

    info!("HTTP server listening on port {}", config::http::PORT);

    loop {
        Timer::after(Duration::from_secs(60)).await;
    }
}
