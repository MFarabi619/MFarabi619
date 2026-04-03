#![no_std]
#![no_main]

extern crate alloc;

use core::net::Ipv4Addr;

use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Runner, StackResources, tcp::TcpSocket};
use embassy_time::{Duration, Timer, with_timeout};
use esp_hal::{clock::CpuClock, rng::Rng, timer::timg::TimerGroup};
use esp_radio::wifi::{ClientConfig, ModeConfig, WifiController, WifiDevice, WifiEvent};
use panic_rtt_target as _;
use static_cell::StaticCell;

const WIFI_SSID: &str = env!("NETWORK_WIFI_SSID");
const WIFI_PASSWORD: &str = env!("NETWORK_WIFI_PSK");
const HTTP_HOST_ADDRESS: Ipv4Addr = Ipv4Addr::new(216, 239, 32, 21);
const HTTP_HOST_PORT: u16 = 80;
const HTTP_REQUEST: &[u8] = b"GET / HTTP/1.0\r\nHost: www.mobile-j.de\r\n\r\n";

macro_rules! mk_static {
    ($type:ty, $value:expr) => {{
        static STATIC_CELL: StaticCell<$type> = StaticCell::new();
        STATIC_CELL.uninit().write($value)
    }};
}

fn client_mode_config() -> ModeConfig {
    ModeConfig::Client(
        ClientConfig::default()
            .with_ssid(WIFI_SSID.into())
            .with_password(WIFI_PASSWORD.into()),
    )
}

fn random_seed(random_number_generator: &mut Rng) -> u64 {
    (u64::from(random_number_generator.random()) << 32)
        | u64::from(random_number_generator.random())
}

async fn write_request(socket: &mut TcpSocket<'_>, payload: &[u8]) {
    let mut bytes_written = 0;

    while bytes_written < payload.len() {
        let written_this_iteration = socket.write(&payload[bytes_written..]).await.unwrap();
        bytes_written += written_this_iteration;
    }
}

esp_bootloader_esp_idf::esp_app_desc!();

#[embassy_executor::task]
async fn connection_task(mut wifi_controller: WifiController<'static>) {
    loop {
        info!("attempting Wi-Fi connection");

        match wifi_controller.connect_async().await {
            Ok(()) => {
                info!("Wi-Fi connected");
                wifi_controller
                    .wait_for_event(WifiEvent::StaDisconnected)
                    .await;
                info!("Wi-Fi disconnected");
            }
            Err(error) => {
                info!("Wi-Fi connect failed: {:?}", error);
                Timer::after(Duration::from_secs(2)).await;
            }
        }
    }
}

#[embassy_executor::task]
async fn net_task(mut runner: Runner<'static, WifiDevice<'static>>) {
    runner.run().await;
}

#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 64 * 1024);
    esp_alloc::heap_allocator!(size: 64 * 1024);

    let timer_group0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timer_group0.timer0);

    let radio_controller = mk_static!(esp_radio::Controller<'static>, esp_radio::init().unwrap());
    let (mut wifi_controller, interfaces) =
        esp_radio::wifi::new(radio_controller, peripherals.WIFI, Default::default()).unwrap();

    wifi_controller.set_config(&client_mode_config()).unwrap();
    wifi_controller.start_async().await.unwrap();

    let mut random_number_generator = Rng::new();
    let seed = random_seed(&mut random_number_generator);
    let network_config = embassy_net::Config::dhcpv4(Default::default());
    let (stack, runner) = embassy_net::new(
        interfaces.sta,
        network_config,
        mk_static!(StackResources<3>, StackResources::<3>::new()),
        seed,
    );

    spawner.spawn(connection_task(wifi_controller)).unwrap();
    spawner.spawn(net_task(runner)).unwrap();

    with_timeout(Duration::from_secs(25), stack.wait_config_up())
        .await
        .unwrap();

    let ipv4_config = stack.config_v4().unwrap();
    info!("DHCP address acquired: {}", ipv4_config.address);

    let mut receive_buffer = [0u8; 4096];
    let mut transmit_buffer = [0u8; 4096];

    loop {
        let mut socket = TcpSocket::new(stack, &mut receive_buffer, &mut transmit_buffer);
        socket.set_timeout(Some(Duration::from_secs(10)));

        info!("connecting to {}:{}", HTTP_HOST_ADDRESS, HTTP_HOST_PORT);
        socket
            .connect((HTTP_HOST_ADDRESS, HTTP_HOST_PORT))
            .await
            .unwrap();
        write_request(&mut socket, HTTP_REQUEST).await;

        let mut response_buffer = [0u8; 1024];
        let bytes_read = socket.read(&mut response_buffer).await.unwrap();
        info!("read {} byte(s) from remote host", bytes_read);

        socket.close();
        Timer::after(Duration::from_secs(5)).await;
    }
}
