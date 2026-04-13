#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Runner, StackResources, tcp::TcpSocket};
use embassy_time::{Duration, Timer, with_timeout};
use esp_hal::{
    clock::CpuClock,
    interrupt::software::SoftwareInterruptControl,
    rng::Rng,
    system::software_reset,
    timer::timg::TimerGroup,
};
use esp_hal_ota::Ota;
use esp_radio::wifi::{Config, ControllerConfig, Interface, WifiController, sta::StationConfig};
use esp_storage::FlashStorage;
use panic_rtt_target as _;
use static_cell::StaticCell;

const WIFI_SSID: &str = env!("NETWORK_WIFI_SSID");
const WIFI_PASSWORD: &str = env!("NETWORK_WIFI_PSK");
const OTA_LISTEN_PORT: u16 = 3232;

const RX_BUFFER_SIZE: usize = 16384;
const TX_BUFFER_SIZE: usize = 16384;
const OTA_CHUNK_SIZE: usize = 8192;

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
async fn wifi_connection_task(mut wifi_controller: WifiController<'static>) {
    loop {
        info!("attempting Wi-Fi STA connection");

        match wifi_controller.connect_async().await {
            Ok(_connected_info) => {
                info!("Wi-Fi STA connected");
                let _ = wifi_controller.wait_for_disconnect_async().await;
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
async fn wifi_net_task(mut runner: Runner<'static, Interface<'static>>) {
    runner.run().await;
}

async fn read_exact(socket: &mut TcpSocket<'_>, buf: &mut [u8]) -> Result<(), embassy_net::tcp::Error> {
    let mut remaining = buf;
    while !remaining.is_empty() {
        match socket.read(remaining).await {
            Ok(0) => return Err(embassy_net::tcp::Error::ConnectionReset),
            Ok(n) => {
                let (done, rest) = remaining.split_at_mut(n);
                remaining = rest;
                if done.len() != n {
                    break;
                }
            }
            Err(e) => return Err(e),
        }
    }
    Ok(())
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

    {
        let mut ota = Ota::new(FlashStorage::new()).expect("Cannot create OTA");
        if let Err(error) = ota.ota_mark_app_valid() {
            info!("ota_mark_app_valid failed (may be on factory partition): {:?}", error);
        } else {
            info!("marked current OTA slot as valid");
        }
    }

    let station_config = Config::Station(
        StationConfig::default()
            .with_ssid(WIFI_SSID)
            .with_password(WIFI_PASSWORD.into()),
    );

    info!("starting Wi-Fi in STA mode");
    let (wifi_controller, interfaces) = esp_radio::wifi::new(
        peripherals.WIFI,
        ControllerConfig::default().with_initial_config(station_config),
    )
    .expect("Failed to initialize Wi-Fi controller");

    info!("attempting STA connection to '{}'", WIFI_SSID);

    let mut random_number_generator = Rng::new();
    let seed = random_seed(&mut random_number_generator);

    let network_config = embassy_net::Config::dhcpv4(Default::default());
    let (stack, runner) = embassy_net::new(
        interfaces.station,
        network_config,
        mk_static!(StackResources<3>, StackResources::<3>::new()),
        seed,
    );

    spawner.spawn(wifi_connection_task(wifi_controller).unwrap());
    spawner.spawn(wifi_net_task(runner).unwrap());

    info!("waiting for STA DHCP configuration...");

    match with_timeout(Duration::from_secs(30), stack.wait_config_up()).await {
        Ok(()) => {
            if let Some(ip_config) = stack.config_v4() {
                info!("STA connected with IP: {}", ip_config.address);
            } else {
                info!("STA DHCP completed but no IPv4 config available");
            }
        }
        Err(_) => {
            info!("STA DHCP timed out after 30s");
        }
    }

    loop {
        if stack.is_link_up() {
            info!("network link is up");
            break;
        }
        Timer::after(Duration::from_millis(500)).await;
    }

    info!("OTA receiver listening on TCP port {}", OTA_LISTEN_PORT);

    loop {
        static mut RX_BUFF: [u8; RX_BUFFER_SIZE] = [0; RX_BUFFER_SIZE];
        static mut TX_BUFF: [u8; TX_BUFFER_SIZE] = [0; TX_BUFFER_SIZE];

        let mut socket = unsafe {
            TcpSocket::new(
                stack,
                &mut *core::ptr::addr_of_mut!(RX_BUFF),
                &mut *core::ptr::addr_of_mut!(TX_BUFF),
            )
        };

        socket.set_timeout(Some(Duration::from_secs(10)));

        match socket.accept(OTA_LISTEN_PORT).await {
            Ok(()) => {
                if let Some(remote) = socket.remote_endpoint() {
                    info!("host connected from {}", remote);
                } else {
                    info!("host connected, remote endpoint unavailable");
                }

                info!("receiving firmware header");
                let mut header_buffer = [0u8; 8];
                if let Err(error) = read_exact(&mut socket, &mut header_buffer).await {
                    info!("failed to read firmware header: {:?}", error);
                    Timer::after(Duration::from_secs(5)).await;
                    continue;
                }

                let firmware_size = u32::from_le_bytes(header_buffer[..4].try_into().unwrap());
                let target_crc = u32::from_le_bytes(header_buffer[4..8].try_into().unwrap());

                info!("firmware size: {} bytes, target CRC: {:#010x}", firmware_size, target_crc);

                let mut ota = Ota::new(FlashStorage::new()).expect("Cannot create OTA");
                ota.ota_begin(firmware_size, target_crc).expect("ota_begin failed");

                let mut ota_chunk_buffer = [0u8; OTA_CHUNK_SIZE];
                let mut bytes_received_total: usize = 0;
                let mut last_reported_percent: u32 = 0;

                loop {
                    let bytes_to_read = OTA_CHUNK_SIZE.min(firmware_size as usize - bytes_received_total);
                    if bytes_to_read == 0 {
                        break;
                    }

                    if let Err(error) = read_exact(&mut socket, &mut ota_chunk_buffer[..bytes_to_read]).await {
                        info!("failed to read firmware chunk: {:?}", error);
                        Timer::after(Duration::from_secs(5)).await;
                        break;
                    }

                    let write_complete = ota
                        .ota_write_chunk(&ota_chunk_buffer[..bytes_to_read])
                        .expect("ota_write_chunk failed");

                    bytes_received_total += bytes_to_read;

                    let progress = (bytes_received_total as u32 * 100) / firmware_size;
                    if progress >= last_reported_percent + 5 || progress == 100 {
                        info!(
                            "OTA progress: {}% ({}/{} bytes)",
                            progress,
                            bytes_received_total,
                            firmware_size
                        );
                        last_reported_percent = progress;
                    }

                    socket.write(&[0]).await.ok();

                    if write_complete {
                        break;
                    }
                }

                info!("firmware received, flushing OTA");

                match ota.ota_flush(false, true) {
                    Ok(()) => {
                        info!("OTA complete! Rebooting into new firmware");
                        Timer::after(Duration::from_millis(1000)).await;
                        software_reset();
                    }
                    Err(error) => {
                        info!("OTA flush failed: {:?}", error);
                        Timer::after(Duration::from_secs(5)).await;
                    }
                }
                software_reset();
            }
            Err(error) => {
                info!("failed to accept OTA connection, retrying in 5s: {:?}", error);
                Timer::after(Duration::from_secs(5)).await;
            }
        }
    }
}
