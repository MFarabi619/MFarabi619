#![no_std]
#![no_main]

use core::{fmt::Write as _, net::Ipv4Addr};

use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Runner, StackResources, tcp::TcpSocket};
use embassy_time::{Duration, Instant, Timer, with_timeout};
use esp_hal::{clock::CpuClock, rng::Rng, timer::timg::TimerGroup};
use esp_radio::wifi::{ClientConfig, ModeConfig, WifiController, WifiDevice, WifiEvent};
use panic_rtt_target as _;
use static_cell::StaticCell;

const WIFI_SSID: &str = env!("NETWORK_WIFI_SSID");
const WIFI_PASSWORD: &str = env!("NETWORK_WIFI_PSK");
const TCP_LISTEN_PORT: u16 = 4040;

const RECEIVE_BUFFER_SIZE: usize = 4096;
const TRANSMIT_BUFFER_SIZE: usize = 4096;

macro_rules! mk_static {
    ($type:ty, $value:expr) => {{
        static STATIC_CELL: StaticCell<$type> = StaticCell::new();
        STATIC_CELL.uninit().write($value)
    }};
}

esp_bootloader_esp_idf::esp_app_desc!();

fn build_wifi_mode_config() -> ModeConfig {
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

async fn write_all(socket: &mut TcpSocket<'_>, payload: &[u8]) -> Result<(), embassy_net::tcp::Error> {
    let mut bytes_written_total = 0;

    while bytes_written_total < payload.len() {
        let bytes_written_this_iteration = socket.write(&payload[bytes_written_total..]).await?;
        if bytes_written_this_iteration == 0 {
            return Err(embassy_net::tcp::Error::ConnectionReset);
        }
        bytes_written_total += bytes_written_this_iteration;
    }

    Ok(())
}

#[embassy_executor::task]
async fn wifi_connection_task(mut wifi_controller: WifiController<'static>) {
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

    let timer_group0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timer_group0.timer0);

    let radio_controller = mk_static!(esp_radio::Controller<'static>, esp_radio::init().unwrap());
    let (mut wifi_controller, interfaces) =
        esp_radio::wifi::new(radio_controller, peripherals.WIFI, Default::default()).unwrap();

    wifi_controller.set_config(&build_wifi_mode_config()).unwrap();
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

    spawner.spawn(wifi_connection_task(wifi_controller)).unwrap();
    spawner.spawn(network_task(runner)).unwrap();

    with_timeout(Duration::from_secs(30), stack.wait_config_up())
        .await
        .unwrap();

    let ipv4_config = stack.config_v4().unwrap();
    info!("DHCP address acquired: {}", ipv4_config.address);
    info!("listening for TCP log client on {}:{}", Ipv4Addr::UNSPECIFIED, TCP_LISTEN_PORT);

    loop {
        static mut RECEIVE_BUFFER: [u8; RECEIVE_BUFFER_SIZE] = [0; RECEIVE_BUFFER_SIZE];
        static mut TRANSMIT_BUFFER: [u8; TRANSMIT_BUFFER_SIZE] = [0; TRANSMIT_BUFFER_SIZE];

        let mut socket = unsafe {
            TcpSocket::new(
                stack,
                &mut *core::ptr::addr_of_mut!(RECEIVE_BUFFER),
                &mut *core::ptr::addr_of_mut!(TRANSMIT_BUFFER),
            )
        };

        socket.set_timeout(Some(Duration::from_secs(5)));

        match socket.accept(TCP_LISTEN_PORT).await {
            Ok(()) => {
                info!("TCP log client connected: {:?}", socket.remote_endpoint());

                let welcome_message = b"defmt-tcp proof-of-concept stream connected\n";
                if let Err(error) = write_all(&mut socket, welcome_message).await {
                    info!("failed to send welcome message: {:?}", error);
                    continue;
                }

                let mut sample_counter: u32 = 0;

                loop {
                    sample_counter = sample_counter.wrapping_add(1);
                    let uptime_milliseconds = Instant::now().as_millis();

                    let mut text_line = heapless::String::<128>::new();
                    let _ = writeln!(
                        &mut text_line,
                        "sample={} uptime_ms={} note=mirror-defmt-over-tcp",
                        sample_counter,
                        uptime_milliseconds
                    );

                    info!(
                        "streamed TCP log sample={} uptime_ms={}",
                        sample_counter,
                        uptime_milliseconds
                    );

                    if let Err(error) = write_all(&mut socket, text_line.as_bytes()).await {
                        info!("TCP log stream disconnected: {:?}", error);
                        break;
                    }

                    Timer::after(Duration::from_secs(1)).await;
                }
            }
            Err(error) => {
                info!("TCP accept failed: {:?}", error);
                Timer::after(Duration::from_millis(250)).await;
            }
        }
    }
}
