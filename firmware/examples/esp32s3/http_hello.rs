#![no_std]
#![no_main]
#![feature(impl_trait_in_assoc_type)]

extern crate alloc;

use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Runner, StackResources};
use embassy_time::{Duration, Timer, with_timeout};
use esp_hal::{
    clock::CpuClock,
    interrupt::software::SoftwareInterruptControl,
    rng::Rng,
    timer::timg::TimerGroup,
};
use esp_radio::wifi::{Config, ControllerConfig, Interface, WifiController, sta::StationConfig};
use panic_rtt_target as _;
use picoserve::AppBuilder;
use static_cell::StaticCell;

use firmware::{config, services::http::HttpAppProps};

const WIFI_SSID: &str = env!("NETWORK_WIFI_SSID");
const WIFI_PASSWORD: &str = env!("NETWORK_WIFI_PSK");

macro_rules! mk_static {
    ($type:ty, $value:expr) => {{
        static STATIC_CELL: StaticCell<$type> = StaticCell::new();
        STATIC_CELL.uninit().write($value)
    }};
}

esp_bootloader_esp_idf::esp_app_desc!();

fn random_seed(rng: &mut Rng) -> u64 {
    (u64::from(rng.random()) << 32) | u64::from(rng.random())
}

#[embassy_executor::task]
async fn wifi_connection_task(mut ctrl: WifiController<'static>) {
    loop {
        info!("attempting Wi-Fi connection");
        match ctrl.connect_async().await {
            Ok(_connected_info) => {
                info!("Wi-Fi connected");
                let _ = ctrl.wait_for_disconnect_async().await;
            }
            Err(e) => {
                info!("Wi-Fi connect failed: {:?}", e);
                Timer::after(Duration::from_secs(2)).await;
            }
        }
    }
}

#[embassy_executor::task]
async fn network_task(mut runner: Runner<'static, Interface<'static>>) {
    runner.run().await;
}

#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 64 * 1024);
    esp_alloc::heap_allocator!(size: 64 * 1024);

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    let sw_ints = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
    esp_rtos::start(timg0.timer0, sw_ints.software_interrupt0);

    let station_config = Config::Station(
        StationConfig::default()
            .with_ssid(WIFI_SSID)
            .with_password(WIFI_PASSWORD.into()),
    );

    let (wifi_ctrl, interfaces) = esp_radio::wifi::new(
        peripherals.WIFI,
        ControllerConfig::default().with_initial_config(station_config),
    )
    .unwrap();

    let mut rng = Rng::new();
    let (stack, runner) = embassy_net::new(
        interfaces.station,
        embassy_net::Config::dhcpv4(Default::default()),
        mk_static!(StackResources<3>, StackResources::<3>::new()),
        random_seed(&mut rng),
    );

    spawner.spawn(wifi_connection_task(wifi_ctrl).unwrap());
    spawner.spawn(network_task(runner).unwrap());

    with_timeout(Duration::from_secs(30), stack.wait_config_up())
        .await
        .unwrap();

    info!("DHCP: {}", stack.config_v4().unwrap().address);

    let app = mk_static!(
        picoserve::AppRouter<HttpAppProps>,
        HttpAppProps { stack }.build_app()
    );

    spawner.spawn(firmware::services::http::task(0, stack, app).unwrap());

    info!("HTTP server on port {}", config::http::PORT);

    loop {
        Timer::after(Duration::from_secs(60)).await;
    }
}
