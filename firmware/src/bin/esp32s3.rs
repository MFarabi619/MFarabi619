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

use config::WifiCredentials;
use core::fmt::Write;
use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Runner, Stack, StackResources, tcp::TcpSocket};
use embassy_time::{Duration, Instant, Ticker, Timer};
use esp_hal::{
    clock::CpuClock,
    delay::Delay,
    gpio::{Level, Output, OutputConfig},
    i2c::master::{Config as I2cConfig, I2c},
    rng::Rng,
    system::software_reset,
    time::Rate,
    timer::timg::TimerGroup,
};
use esp_hal_ota::Ota;
use esp_radio::{
    ble::controller::BleConnector,
    wifi::{ClientConfig, ModeConfig, WifiController, WifiDevice, WifiEvent},
};
use esp_storage::FlashStorage;
use bt_hci::controller::ExternalController;
use heapless::String as HeaplessString;
use panic_rtt_target as _;
use static_cell::StaticCell;
use trouble_host::prelude::*;

use firmware::drivers::{i2c as i2c_driver, sd_card};
use firmware::modules::state::{self, AppState};
use firmware::modules::web_server::routes::{self, HTTP_SERVER_PORT};
use firmware::modules::sensors::temperature_humidity;

const CONNECTIONS_MAX: usize = 1;
const L2CAP_CHANNELS_MAX: usize = 1;

const OTA_DEVICE_PORT: u16 = 3232;
const OTA_RX_BUFFER_SIZE: usize = 16384;
const OTA_TX_BUFFER_SIZE: usize = 16384;
const OTA_CHUNK_SIZE: usize = 8192;
const OTA_STATUS_READY: u8 = 0xA5;
const OTA_STATUS_BEGIN_FAILED: u8 = 0xE1;

const TEMPERATURE_HUMIDITY_MUX_CHANNEL: u8 = 0;

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
                state::WIFI_INITIALIZED.store(true, core::sync::atomic::Ordering::Release);
                let _ = wifi_controller
                    .wait_for_event(WifiEvent::StaDisconnected)
                    .await;
                state::WIFI_INITIALIZED.store(false, core::sync::atomic::Ordering::Release);
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
async fn temperature_humidity_logger_task(mut i2c_bus: I2c<'static, esp_hal::Async>) {
    let mut sampling_interval = Ticker::every(Duration::from_secs(5));
    let mut discovered_sensor_address: Option<u8> = None;

    loop {
        sampling_interval.next().await;

        if let Err(error_message) =
            i2c_driver::select_mux_channel(&mut i2c_bus, TEMPERATURE_HUMIDITY_MUX_CHANNEL).await
        {
            info!(
                "failed to select I2C mux channel {}: {}",
                TEMPERATURE_HUMIDITY_MUX_CHANNEL, error_message
            );
            continue;
        }

        if discovered_sensor_address.is_none() {
            discovered_sensor_address =
                i2c_driver::discover_sensor_address(&mut i2c_bus).await;
            if let Some(sensor_address) = discovered_sensor_address {
                info!(
                    "temperature/humidity sensor found on mux channel {} at I2C address {:#04x}",
                    TEMPERATURE_HUMIDITY_MUX_CHANNEL, sensor_address
                );
            } else {
                info!(
                    "temperature/humidity sensor not found on mux channel {}, retrying",
                    TEMPERATURE_HUMIDITY_MUX_CHANNEL
                );
                continue;
            }
        }

        let sensor_address = discovered_sensor_address.unwrap();

        match temperature_humidity::read_once(&mut i2c_bus, sensor_address).await {
            Ok((temperature_celsius, relative_humidity_percent)) => {
                let timestamp_millis = Instant::now().as_millis();
                let mut data_csv_line = HeaplessString::<192>::new();

                if write!(
                    data_csv_line,
                    "{},{:.2},{:.2},,,,,,,,\n",
                    timestamp_millis, temperature_celsius, relative_humidity_percent
                )
                .is_err()
                {
                    info!("failed to format data.csv row");
                    continue;
                }

                if let Err(error_message) = sd_card::append_data_csv_line(data_csv_line.as_str()) {
                    info!("failed to append data.csv row: {}", error_message);
                } else {
                    info!(
                        "logged temp/humidity sample: temperature={}C humidity={}%%",
                        temperature_celsius, relative_humidity_percent
                    );
                }
            }
            Err(error_message) => {
                info!(
                    "failed to read temp/humidity sensor on mux channel {}: {}",
                    TEMPERATURE_HUMIDITY_MUX_CHANNEL, error_message
                );
            }
        }
    }
}

async fn read_exact(
    socket: &mut TcpSocket<'_>,
    buf: &mut [u8],
) -> Result<(), embassy_net::tcp::Error> {
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

                let firmware_size =
                    u32::from_le_bytes(header_buffer[..4].try_into().unwrap());
                let target_crc =
                    u32::from_le_bytes(header_buffer[4..8].try_into().unwrap());

                info!(
                    "OTA header received: size={} bytes crc={:#010x}",
                    firmware_size, target_crc
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

                state::FIRMWARE_UPGRADE_IN_PROGRESS
                    .store(true, core::sync::atomic::Ordering::Release);

                if let Err(error) = ota.ota_begin(firmware_size, target_crc) {
                    info!("ota_begin failed: {:?}", error);
                    let _ = socket.write(&[OTA_STATUS_BEGIN_FAILED]).await;
                    state::FIRMWARE_UPGRADE_IN_PROGRESS
                        .store(false, core::sync::atomic::Ordering::Release);
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                if socket.write(&[OTA_STATUS_READY]).await.is_err() {
                    info!("failed to send OTA ready status");
                    state::FIRMWARE_UPGRADE_IN_PROGRESS
                        .store(false, core::sync::atomic::Ordering::Release);
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                let mut chunk_buffer = [0u8; OTA_CHUNK_SIZE];
                let mut bytes_received_total = 0usize;
                let mut last_reported_percent = 0u32;

                let ota_write_result: Result<(), ()> = loop {
                    let bytes_remaining =
                        (firmware_size as usize).saturating_sub(bytes_received_total);
                    if bytes_remaining == 0 {
                        break Ok(());
                    }

                    let bytes_to_read = bytes_remaining.min(OTA_CHUNK_SIZE);
                    if let Err(error) =
                        read_exact(&mut socket, &mut chunk_buffer[..bytes_to_read]).await
                    {
                        info!("failed to read OTA chunk: {:?}", error);
                        break Err(());
                    }

                    let write_complete =
                        match ota.ota_write_chunk(&chunk_buffer[..bytes_to_read]) {
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
                            progress, bytes_received_total, firmware_size
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

                state::FIRMWARE_UPGRADE_IN_PROGRESS
                    .store(false, core::sync::atomic::Ordering::Release);

                if ota_write_result.is_err() {
                    Timer::after(Duration::from_secs(2)).await;
                    continue;
                }

                info!("OTA payload received, flushing update");
                info!(
                    "OTA progress details: {:?}",
                    ota.get_progress_details()
                        .map(|details| (details.remaining, details.last_crc))
                );
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
            info!(
                "ota_mark_app_valid failed (may be on factory partition): {:?}",
                error
            );
        } else {
            info!("marked current OTA slot as valid");
        }
    }

    let _sensor_power_relay =
        Output::new(peripherals.GPIO5, Level::High, OutputConfig::default());
    Delay::new().delay_millis(1_000);

    sd_card::initialize(
        peripherals.SPI2,
        peripherals.GPIO10,
        peripherals.GPIO11,
        peripherals.GPIO12,
        peripherals.GPIO13,
    );
    if let Err(error_message) = sd_card::ensure_data_csv_exists() {
        info!("failed to initialize data.csv: {}", error_message);
    }

    let temperature_humidity_i2c_bus = I2c::new(
        peripherals.I2C0,
        I2cConfig::default().with_frequency(Rate::from_khz(i2c_driver::I2C_BUS_FREQUENCY_KHZ)),
    )
    .unwrap()
    .with_sda(peripherals.GPIO8)
    .with_scl(peripherals.GPIO9)
    .into_async();

    state::set_app_state(AppState {
        cloud_event_source: state::DEFAULT_CLOUD_EVENT_SOURCE,
        cloud_event_type: state::DEFAULT_CLOUD_EVENT_TYPE,
        boot_timestamp_seconds: Instant::now().as_secs(),
    });

    let mut flash = FlashStorage::new();
    let credentials = config::read_credentials(&mut flash).unwrap_or_else(|| {
        info!("no credentials in flash, using defaults");
        WifiCredentials {
            ssid: HeaplessString::try_from(config::DEFAULT_SSID).unwrap(),
            password: HeaplessString::try_from(config::DEFAULT_PASSWORD).unwrap(),
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
    spawner
        .spawn(temperature_humidity_logger_task(temperature_humidity_i2c_bus))
        .unwrap();

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

    spawner
        .spawn(routes::http_server_task(stack))
        .unwrap();
    spawner.spawn(ota_receiver_task(stack)).unwrap();

    info!("HTTP server listening on port {}", HTTP_SERVER_PORT);

    let transport =
        BleConnector::new(radio_init, peripherals.BT, Default::default()).unwrap();
    let ble_controller = ExternalController::<_, 1>::new(transport);
    let mut resources: HostResources<DefaultPacketPool, CONNECTIONS_MAX, L2CAP_CHANNELS_MAX> =
        HostResources::new();
    let _stack = trouble_host::new(ble_controller, &mut resources);

    loop {
        Timer::after(Duration::from_secs(60)).await;
    }
}
