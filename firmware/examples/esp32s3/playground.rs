#![no_std]
#![no_main]

extern crate alloc;

use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Runner, StackResources};
use embassy_time::{Duration, Timer, with_timeout};
use esp_hal::{clock::CpuClock, delay::Delay, rng::Rng, timer::timg::TimerGroup};
use esp_radio::wifi::{ClientConfig, ModeConfig, WifiController, WifiDevice, WifiEvent};
use panic_rtt_target as _;
use static_cell::StaticCell;

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
            Ok(()) => {
                info!("Wi-Fi connected");
                ctrl.wait_for_event(WifiEvent::StaDisconnected).await;
            }
            Err(e) => {
                info!("Wi-Fi connect failed: {:?}", e);
                Timer::after(Duration::from_secs(2)).await;
            }
        }
    }
}

#[embassy_executor::task]
async fn network_task(mut runner: Runner<'static, WifiDevice<'static>>) {
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
    esp_rtos::start(timg0.timer0);

    // SD card
    Delay::new().delay_millis(500);
    firmware::filesystems::sd::initialize(
        peripherals.SPI2,
        peripherals.GPIO10,
        peripherals.GPIO11,
        peripherals.GPIO12,
        peripherals.GPIO13,
    );

    let radio = mk_static!(
        esp_radio::Controller<'static>,
        esp_radio::init().unwrap()
    );

    let mode = ModeConfig::Client(
        ClientConfig::default()
            .with_ssid(WIFI_SSID.into())
            .with_password(WIFI_PASSWORD.into()),
    );

    let (mut wifi_ctrl, interfaces) =
        esp_radio::wifi::new(radio, peripherals.WIFI, Default::default()).unwrap();
    wifi_ctrl.set_config(&mode).unwrap();
    wifi_ctrl.start_async().await.unwrap();

    let mut rng = Rng::new();
    let (stack, runner) = embassy_net::new(
        interfaces.sta,
        embassy_net::Config::dhcpv4(Default::default()),
        mk_static!(StackResources<5>, StackResources::<5>::new()),
        random_seed(&mut rng),
    );

    spawner.spawn(wifi_connection_task(wifi_ctrl)).unwrap();
    spawner.spawn(network_task(runner)).unwrap();

    with_timeout(Duration::from_secs(30), stack.wait_config_up())
        .await
        .unwrap();

    info!("DHCP: {}", stack.config_v4().unwrap().address);

    // All shell logic lives in the lib — just spawn it
    spawner
        .spawn(firmware::programs::shell::task(stack))
        .unwrap();

    loop {
        Timer::after(Duration::from_secs(60)).await;
    }
}
