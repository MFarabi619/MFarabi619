#![no_std]
#![no_main]
#![deny(
    clippy::mem_forget,
    reason = "mem::forget is generally not safe to do with esp_hal types, especially those \
    holding buffers for the duration of a data transfer."
)]
#![deny(clippy::large_stack_frames)]

extern crate alloc;

#[path = "../config.rs"]
mod config;

use bt_hci::controller::ExternalController;
use config::WifiCredentials;
use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Runner, Stack, StackResources, tcp::TcpSocket};
use embassy_time::{Duration, Timer};
use esp_hal::{clock::CpuClock, rng::Rng, system::software_reset, timer::timg::TimerGroup};
use esp_hal_ota::Ota;
use esp_radio::{
    ble::controller::BleConnector,
    wifi::{ClientConfig, ModeConfig, WifiController, WifiDevice, WifiEvent},
};
use esp_storage::FlashStorage;
use heapless::String;
use panic_rtt_target as _;
use picoserve::routing::get;
use static_cell::StaticCell;
use trouble_host::prelude::*;

const CONNECTIONS_MAX: usize = 1;
const L2CAP_CHANNELS_MAX: usize = 1;

const HTTP_SERVER_PORT: u16 = 80;
const OTA_DEVICE_PORT: u16 = 3232;

const OTA_RX_BUFFER_SIZE: usize = 16384;
const OTA_TX_BUFFER_SIZE: usize = 16384;
const OTA_CHUNK_SIZE: usize = 8192;

const OTA_STATUS_READY: u8 = 0xA5;
const OTA_STATUS_BEGIN_FAILED: u8 = 0xE1;

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

fn build_sta_config(credentials: &WifiCredentials) -> ModeConfig {
    ModeConfig::Client(
        ClientConfig::default()
            .with_ssid(credentials.ssid.as_str().into())
            .with_password(credentials.password.as_str().into()),
    )
}

#[embassy_executor::task]
async fn wifi_connection_task(mut wifi_controller: WifiController<'static>) {
    loop {
        info!("attempting Wi-Fi STA connection");

        match wifi_controller.connect_async().await {
            Ok(()) => {
                info!("Wi-Fi STA connected");
                let _ = wifi_controller
                    .wait_for_event(WifiEvent::StaDisconnected)
                    .await;
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
async fn wifi_net_task(mut runner: Runner<'static, WifiDevice<'static>>) {
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
                    "<!DOCTYPE html><html><head><title>Ceratina</title></head><body>",
                    "<h1>Ceratina Device</h1>",
                    "<p>HTTP server is running.</p>",
                    "</body></html>",
                ),
            )
        }),
    );

    let config = mk_static!(
        picoserve::Config<Duration>,
        picoserve::Config::new(picoserve::Timeouts {
            start_read_request: Some(Duration::from_secs(5)),
            persistent_start_read_request: Some(Duration::from_secs(5)),
            read_request: Some(Duration::from_secs(2)),
            write: Some(Duration::from_secs(2)),
        })
        .keep_connection_alive()
    );

    let mut tcp_rx_buffer = [0u8; 2048];
    let mut tcp_tx_buffer = [0u8; 2048];
    let mut http_buffer = [0u8; 4096];

    loop {
        picoserve::listen_and_serve(
            0usize,
            &app,
            config,
            stack,
            HTTP_SERVER_PORT,
            &mut tcp_rx_buffer,
            &mut tcp_tx_buffer,
            &mut http_buffer,
        )
        .await;
    }
}

async fn read_exact(socket: &mut TcpSocket<'_>, buf: &mut [u8]) -> Result<(), embassy_net::tcp::Error> {
    let mut offset = 0;
    while offset < buf.len() {
        match socket.read(&mut buf[offset..]).await {
            Ok(0) => return Err(embassy_net::tcp::Error::ConnectionReset),
            Ok(bytes_read) => {
                offset += bytes_read;
            }
            Err(error) => return Err(error),
        }
    }

    Ok(())
}

#[embassy_executor::task]
async fn ota_receiver_task(stack: Stack<'static>) {
    info!("OTA receiver listening on TCP port {}", OTA_DEVICE_PORT);

    loop {
        static mut RX_BUFFER: [u8; OTA_RX_BUFFER_SIZE] = [0; OTA_RX_BUFFER_SIZE];
        static mut TX_BUFFER: [u8; OTA_TX_BUFFER_SIZE] = [0; OTA_TX_BUFFER_SIZE];

        let mut socket = unsafe {
            TcpSocket::new(
                stack,
                &mut *core::ptr::addr_of_mut!(RX_BUFFER),
                &mut *core::ptr::addr_of_mut!(TX_BUFFER),
            )
        };

        socket.set_timeout(Some(Duration::from_secs(10)));

        match socket.accept(OTA_DEVICE_PORT).await {
            Ok(()) => {
                if let Some(remote) = socket.remote_endpoint() {
                    info!("OTA host connected from {}", remote);
                } else {
                    info!("OTA host connected (remote endpoint unavailable)");
                }

                let mut header_buffer = [0u8; 8];
                if let Err(error) = read_exact(&mut socket, &mut header_buffer).await {
                    info!("failed to read OTA header: {:?}", error);
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                let firmware_size = u32::from_le_bytes(header_buffer[..4].try_into().unwrap());
                let target_crc = u32::from_le_bytes(header_buffer[4..8].try_into().unwrap());

                info!(
                    "OTA header received: size={} bytes crc={:#010x}",
                    firmware_size,
                    target_crc
                );

                let mut ota = match Ota::new(FlashStorage::new()) {
                    Ok(ota) => ota,
                    Err(error) => {
                        info!("failed to create OTA instance: {:?}", error);
                        Timer::after(Duration::from_secs(2)).await;
                        continue;
                    }
                };

                info!(
                    "OTA booted partition: {:?}, next target partition: {:?}, image state: {:?}",
                    ota.get_currently_booted_partition(),
                    ota.get_next_ota_partition(),
                    ota.get_ota_image_state()
                );

                if let Err(error) = ota.ota_begin(firmware_size, target_crc) {
                    info!("ota_begin failed: {:?}", error);
                    let _ = socket.write(&[OTA_STATUS_BEGIN_FAILED]).await;
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                if socket.write(&[OTA_STATUS_READY]).await.is_err() {
                    info!("failed to send OTA ready status");
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                let mut chunk_buffer = [0u8; OTA_CHUNK_SIZE];
                let mut bytes_received_total = 0usize;
                let mut last_reported_percent = 0u32;

                let ota_write_result: Result<(), ()> = loop {
                    let bytes_remaining = (firmware_size as usize).saturating_sub(bytes_received_total);
                    if bytes_remaining == 0 {
                        break Ok(());
                    }

                    let bytes_to_read = bytes_remaining.min(OTA_CHUNK_SIZE);
                    if let Err(error) = read_exact(&mut socket, &mut chunk_buffer[..bytes_to_read]).await {
                        info!("failed to read OTA chunk: {:?}", error);
                        break Err(());
                    }

                    let write_complete = match ota.ota_write_chunk(&chunk_buffer[..bytes_to_read]) {
                        Ok(is_done) => is_done,
                        Err(error) => {
                            info!("ota_write_chunk failed: {:?}", error);
                            break Err(());
                        }
                    };

                    bytes_received_total += bytes_to_read;

                    let progress = (ota.get_ota_progress() * 100.0) as u32;
                    if progress >= last_reported_percent + 5 || progress == 100 {
                        info!(
                            "OTA progress: {}% ({}/{} bytes)",
                            progress,
                            bytes_received_total,
                            firmware_size
                        );
                        last_reported_percent = progress;
                    }

                    if socket.write(&[0]).await.is_err() {
                        info!("failed to ACK OTA chunk");
                        break Err(());
                    }

                    if write_complete {
                        break Ok(());
                    }
                };

                if ota_write_result.is_err() {
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                info!("OTA payload received, flushing update");
                info!("OTA progress details: {:?}", ota.get_progress_details().map(|d| (d.remaining, d.last_crc)));
                match ota.ota_flush(true, true) {
                    Ok(()) => {
                        info!("OTA complete, rebooting into new firmware");
                        Timer::after(Duration::from_millis(1000)).await;
                        software_reset();
                    }
                    Err(error) => {
                        info!("ota_flush failed: {:?}", error);
                        Timer::after(Duration::from_secs(2)).await;
                    }
                }
            }
            Err(error) => {
                info!("OTA accept failed: {:?}", error);
                Timer::after(Duration::from_secs(2)).await;
            }
        }
    }
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

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timg0.timer0);

    info!("Embassy initialized!");

    {
        let mut ota = Ota::new(FlashStorage::new()).expect("Cannot create OTA");
        if let Err(error) = ota.ota_mark_app_valid() {
            info!("ota_mark_app_valid failed (may be on factory partition): {:?}", error);
        } else {
            info!("marked current OTA slot as valid");
        }
    }

    let mut flash = FlashStorage::new();
    let credentials = config::read_credentials(&mut flash).unwrap_or_else(|| {
        info!("no credentials in flash, using defaults");
        WifiCredentials {
            ssid: String::try_from(config::DEFAULT_SSID).unwrap(),
            password: String::try_from(config::DEFAULT_PASSWORD).unwrap(),
        }
    });

    let radio_init = mk_static!(
        esp_radio::Controller<'static>,
        esp_radio::init().expect("Failed to initialize Wi-Fi/BLE controller")
    );

    let mode_config = build_sta_config(&credentials);

    info!(
        "starting Wi-Fi in STA mode with ssid='{}'",
        credentials.ssid
    );
    let (mut wifi_controller, interfaces) = esp_radio::wifi::new(
        radio_init,
        peripherals.WIFI,
        esp_radio::wifi::Config::default(),
    )
    .expect("Failed to initialize Wi-Fi controller");

    wifi_controller.set_config(&mode_config).unwrap();
    wifi_controller
        .start_async()
        .await
        .expect("Failed to start Wi-Fi");

    info!("attempting STA connection to '{}'", credentials.ssid);

    let mut random_number_generator = Rng::new();
    let seed = random_seed(&mut random_number_generator);

    let network_config = embassy_net::Config::dhcpv4(Default::default());
    let (stack, runner) = embassy_net::new(
        interfaces.sta,
        network_config,
        mk_static!(StackResources<5>, StackResources::<5>::new()),
        seed,
    );

    spawner
        .spawn(wifi_connection_task(wifi_controller))
        .unwrap();
    spawner.spawn(wifi_net_task(runner)).unwrap();

    info!("waiting for STA DHCP configuration...");
    loop {
        if let Some(ip_config) = stack.config_v4() {
            info!("STA connected with IP: {}", ip_config.address);
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

    spawner.spawn(http_server_task(stack)).unwrap();
    spawner.spawn(ota_receiver_task(stack)).unwrap();

    info!("HTTP server listening on port {}", HTTP_SERVER_PORT);

    let transport = BleConnector::new(radio_init, peripherals.BT, Default::default()).unwrap();
    let ble_controller = ExternalController::<_, 1>::new(transport);
    let mut resources: HostResources<DefaultPacketPool, CONNECTIONS_MAX, L2CAP_CHANNELS_MAX> =
        HostResources::new();
    let _stack = trouble_host::new(ble_controller, &mut resources);

    loop {
        Timer::after(Duration::from_secs(60)).await;
    }
}
