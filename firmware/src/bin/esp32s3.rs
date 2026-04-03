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

use alloc::string::String as AllocString;
use bt_hci::controller::ExternalController;
use config::WifiCredentials;
use defmt::info;
use embassy_executor::Spawner;
use embassy_net::{Runner, Stack, StackResources, tcp::TcpSocket};
use embassy_time::{Duration, Instant, Ticker, Timer};
use embedded_sdmmc::{Mode, SdCard, TimeSource, Timestamp, VolumeIdx, VolumeManager};
use esp_hal::{
    clock::CpuClock,
    delay::Delay,
    gpio::{Level, Output, OutputConfig},
    i2c::master::{Config as I2cConfig, I2c},
    peripherals::{GPIO10, GPIO11, GPIO12, GPIO13, SPI2},
    rng::Rng,
    spi::{
        Mode as SpiMode,
        master::{Config as SpiConfig, Spi},
    },
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
use heapless::{String as HeaplessString, Vec as HeaplessVec};
use panic_rtt_target as _;
use picoserve::{response::IntoResponse, response::StatusCode, routing::get, routing::get_service, routing::parse_path_segment};
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

const SD_CHIP_SELECT_GPIO_PIN: u32 = 10;
const SD_MOSI_GPIO_PIN: u32 = 11;
const SD_SPI_CLOCK_GPIO_PIN: u32 = 12;
const SD_MISO_GPIO_PIN: u32 = 13;
const SD_SPI_INIT_FREQUENCY_KHZ: u32 = 400;
const SD_CARD_STARTUP_CLOCK_BYTES: [u8; 10] = [0xFF; 10];

const DATA_CSV_FILE_NAME: &str = "data.csv";
const DATA_CSV_HEADER_LINE: &str = "timestamp,temperature_celcius_0,humidity_percent_0,temperature_celcius_1,humidity_percent_1,temperature_celcius_2,humidity_percent_2,voltage_channel_0,voltage_channel_1,voltage_channel_2,voltage_channel_3";
const SYSTEM_DEVICE_STATUS_SOURCE: &str =
    "urn:apidae-systems:tenant:p-uot-ins:site:university-of-ottawa";
const SYSTEM_DEVICE_STATUS_TYPE: &str = "com.apidae.system.device.status.v1";
const FILE_UPLOAD_MAX_BYTES: usize = 4096;

const I2C_BUS_FREQUENCY_KHZ: u32 = 100;
const I2C_MUX_ADDRESS: u8 = 0x70;
const TEMPERATURE_HUMIDITY_MUX_CHANNEL: u8 = 0;
const SENSOR_CANDIDATE_ADDRESSES: [u8; 4] = [0x44, 0x45, 0x46, 0x47];
const SENSOR_MEASUREMENT_COMMAND: [u8; 2] = [0x24, 0x00];

type SdSpiBus = Spi<'static, esp_hal::Blocking>;
type SdChipSelectOutput = Output<'static>;
type SdSpiDevice = embedded_hal_bus::spi::ExclusiveDevice<SdSpiBus, SdChipSelectOutput, Delay>;
type SdCardDevice = SdCard<SdSpiDevice, Delay>;
type SdVolumeManager = VolumeManager<SdCardDevice, FixedTimeSource>;

struct SdStorage {
    volume_manager: SdVolumeManager,
}

#[derive(Default)]
struct FixedTimeSource;

impl TimeSource for FixedTimeSource {
    fn get_timestamp(&self) -> Timestamp {
        Timestamp::from_calendar(2026, 4, 3, 12, 0, 0).unwrap()
    }
}

static SD_STORAGE: critical_section::Mutex<core::cell::RefCell<Option<SdStorage>>> =
    critical_section::Mutex::new(core::cell::RefCell::new(None));

esp_bootloader_esp_idf::esp_app_desc!();

macro_rules! mk_static {
    ($type:ty, $value:expr) => {{
        static STATIC_CELL: StaticCell<$type> = StaticCell::new();
        STATIC_CELL.uninit().write($value)
    }};
}

fn create_sd_spi_bus_and_chip_select(
    sd_spi_peripheral: SPI2<'static>,
    sd_spi_clock_gpio: GPIO12<'static>,
    sd_mosi_gpio: GPIO11<'static>,
    sd_miso_gpio: GPIO13<'static>,
    sd_chip_select_gpio: GPIO10<'static>,
) -> (SdSpiBus, SdChipSelectOutput) {
    let mut sd_spi_bus = Spi::new(
        sd_spi_peripheral,
        SpiConfig::default()
            .with_frequency(Rate::from_khz(SD_SPI_INIT_FREQUENCY_KHZ))
            .with_mode(SpiMode::_0),
    )
    .unwrap()
    .with_sck(sd_spi_clock_gpio)
    .with_mosi(sd_mosi_gpio)
    .with_miso(sd_miso_gpio);

    sd_spi_bus.write(&SD_CARD_STARTUP_CLOCK_BYTES).unwrap();

    let sd_chip_select_output = Output::new(
        sd_chip_select_gpio,
        Level::High,
        OutputConfig::default(),
    );

    (sd_spi_bus, sd_chip_select_output)
}

fn initialize_sd_storage(
    sd_spi_peripheral: SPI2<'static>,
    sd_chip_select_gpio: GPIO10<'static>,
    sd_mosi_gpio: GPIO11<'static>,
    sd_spi_clock_gpio: GPIO12<'static>,
    sd_miso_gpio: GPIO13<'static>,
) {
    let (sd_spi_bus, sd_chip_select_output) = create_sd_spi_bus_and_chip_select(
        sd_spi_peripheral,
        sd_spi_clock_gpio,
        sd_mosi_gpio,
        sd_miso_gpio,
        sd_chip_select_gpio,
    );

    let sd_spi_device =
        embedded_hal_bus::spi::ExclusiveDevice::new(sd_spi_bus, sd_chip_select_output, Delay::new())
            .unwrap();
    let sd_card = SdCard::new(sd_spi_device, Delay::new());

    if let Ok(sd_card_capacity_bytes) = sd_card.num_bytes() {
        info!(
            "SD card detected on SPI (CS=GPIO{}, MOSI=GPIO{}, SCK=GPIO{}, MISO=GPIO{}, size={} MiB)",
            SD_CHIP_SELECT_GPIO_PIN,
            SD_MOSI_GPIO_PIN,
            SD_SPI_CLOCK_GPIO_PIN,
            SD_MISO_GPIO_PIN,
            sd_card_capacity_bytes / (1024 * 1024)
        );
    }

    let sd_volume_manager = VolumeManager::new(sd_card, FixedTimeSource);

    critical_section::with(|critical_section| {
        SD_STORAGE
            .borrow_ref_mut(critical_section)
            .replace(SdStorage {
                volume_manager: sd_volume_manager,
            });
    });
}

fn with_sd_storage_mut<T>(
    operation: impl FnOnce(&mut SdStorage) -> Result<T, &'static str>,
) -> Result<T, &'static str> {
    critical_section::with(|critical_section| {
        let mut sd_storage_option = SD_STORAGE.borrow_ref_mut(critical_section);
        let sd_storage = sd_storage_option.as_mut().ok_or("SD storage not initialized")?;
        operation(sd_storage)
    })
}

fn ensure_data_csv_exists() -> Result<(), &'static str> {
    with_sd_storage_mut(|sd_storage| {
        let volume = sd_storage
            .volume_manager
            .open_volume(VolumeIdx(0))
            .map_err(|_| "failed to open SD volume")?;
        let root_directory = volume
            .open_root_dir()
            .map_err(|_| "failed to open SD root directory")?;

        if let Ok(existing_data_csv_file) = root_directory.open_file_in_dir(DATA_CSV_FILE_NAME, Mode::ReadOnly)
        {
            existing_data_csv_file
                .close()
                .map_err(|_| "failed to close existing data.csv")?;
        } else {
            let data_csv_file = root_directory
                .open_file_in_dir(DATA_CSV_FILE_NAME, Mode::ReadWriteCreateOrTruncate)
                .map_err(|_| "failed to create data.csv")?;
            data_csv_file
                .write(DATA_CSV_HEADER_LINE.as_bytes())
                .map_err(|_| "failed to write data.csv header")?;
            data_csv_file
                .write(b"\n")
                .map_err(|_| "failed to finalize data.csv header")?;
            data_csv_file
                .flush()
                .map_err(|_| "failed to flush data.csv header")?;
            data_csv_file
                .close()
                .map_err(|_| "failed to close newly created data.csv")?;
            info!("created {} with CSV header", DATA_CSV_FILE_NAME);
        }

        root_directory
            .close()
            .map_err(|_| "failed to close SD root directory")?;
        volume.close().map_err(|_| "failed to close SD volume")?;
        Ok(())
    })
}

fn append_data_csv_line(data_csv_line: &str) -> Result<(), &'static str> {
    with_sd_storage_mut(|sd_storage| {
        let volume = sd_storage
            .volume_manager
            .open_volume(VolumeIdx(0))
            .map_err(|_| "failed to open SD volume")?;
        let root_directory = volume
            .open_root_dir()
            .map_err(|_| "failed to open SD root directory")?;

        let data_csv_file = root_directory
            .open_file_in_dir(DATA_CSV_FILE_NAME, Mode::ReadWriteAppend)
            .map_err(|_| "failed to open data.csv for append")?;
        data_csv_file
            .write(data_csv_line.as_bytes())
            .map_err(|_| "failed to append data.csv row")?;
        data_csv_file
            .flush()
            .map_err(|_| "failed to flush appended data.csv row")?;
        data_csv_file
            .close()
            .map_err(|_| "failed to close appended data.csv file")?;

        root_directory
            .close()
            .map_err(|_| "failed to close SD root directory")?;
        volume.close().map_err(|_| "failed to close SD volume")?;
        Ok(())
    })
}

fn list_filesystem_entries_json<const BUFFER_SIZE: usize>() -> Result<HeaplessString<BUFFER_SIZE>, &'static str> {
    use core::fmt::Write;

    with_sd_storage_mut(|sd_storage| {
        let volume = sd_storage
            .volume_manager
            .open_volume(VolumeIdx(0))
            .map_err(|_| "failed to open SD volume")?;
        let root_directory = volume
            .open_root_dir()
            .map_err(|_| "failed to open SD root directory")?;

        let mut entries_json = HeaplessString::<BUFFER_SIZE>::new();
        entries_json
            .push('[')
            .map_err(|_| "filesystem list buffer too small")?;
        let mut is_first_entry = true;
        let mut write_failed = false;

        root_directory
            .iterate_dir(|directory_entry| {
                if write_failed {
                    return;
                }

                if !is_first_entry {
                    if entries_json.push(',').is_err() {
                        write_failed = true;
                        return;
                    }
                }
                is_first_entry = false;

                if write!(
                    entries_json,
                    "{{\"name\":\"{}\",\"size\":{},\"last_write_unix\":0}}",
                    directory_entry.name,
                    directory_entry.size
                )
                .is_err()
                {
                    write_failed = true;
                }
            })
            .map_err(|_| "failed to iterate SD root directory")?;

        if write_failed {
            return Err("filesystem list buffer too small");
        }

        entries_json
            .push(']')
            .map_err(|_| "filesystem list buffer too small")?;

        root_directory
            .close()
            .map_err(|_| "failed to close SD root directory")?;
        volume.close().map_err(|_| "failed to close SD volume")?;
        Ok(entries_json)
    })
}

fn build_json_error_response<const BUFFER_SIZE: usize>(
    error_code: &str,
    error_message: &str,
) -> Result<HeaplessString<BUFFER_SIZE>, &'static str> {
    use core::fmt::Write;

    let mut error_json = HeaplessString::<BUFFER_SIZE>::new();
    write!(
        error_json,
        "{{\"ok\":false,\"error\":{{\"code\":\"{}\",\"message\":\"{}\"}}}}",
        error_code,
        error_message
    )
    .map_err(|_| "error JSON buffer too small")?;

    Ok(error_json)
}

fn build_filesystem_list_json_response<const BUFFER_SIZE: usize>() -> Result<HeaplessString<BUFFER_SIZE>, &'static str> {
    use core::fmt::Write;

    let filesystem_entries_json = list_filesystem_entries_json::<2048>()?;

    let mut list_json = HeaplessString::<BUFFER_SIZE>::new();
    write!(
        list_json,
        "{{\"ok\":true,\"data\":{{\"entries\":{}}}}}",
        filesystem_entries_json
    )
    .map_err(|_| "filesystem list JSON buffer too small")?;

    Ok(list_json)
}

fn is_supported_flat_file_name(file_name: &str) -> bool {
    !file_name.is_empty()
        && !file_name.contains('/')
        && !file_name.contains('\\')
        && !file_name.contains("..")
}

fn read_file_contents<const BUFFER_SIZE: usize>(
    file_name: &str,
) -> Result<HeaplessVec<u8, BUFFER_SIZE>, &'static str> {
    with_sd_storage_mut(|sd_storage| {
        let volume = sd_storage
            .volume_manager
            .open_volume(VolumeIdx(0))
            .map_err(|_| "failed to open SD volume")?;
        let root_directory = volume
            .open_root_dir()
            .map_err(|_| "failed to open SD root directory")?;

        let file = root_directory
            .open_file_in_dir(file_name, Mode::ReadOnly)
            .map_err(|_| "failed to open requested file")?;

        let mut file_contents = HeaplessVec::<u8, BUFFER_SIZE>::new();
        let mut read_chunk_buffer = [0u8; 256];

        while !file.is_eof() {
            let read_byte_count = file
                .read(&mut read_chunk_buffer)
                .map_err(|_| "failed to read file contents")?;
            if read_byte_count == 0 {
                break;
            }

            for &read_byte in &read_chunk_buffer[..read_byte_count] {
                file_contents
                    .push(read_byte)
                    .map_err(|_| "file is larger than response buffer")?;
            }
        }

        file.close().map_err(|_| "failed to close requested file")?;
        root_directory
            .close()
            .map_err(|_| "failed to close SD root directory")?;
        volume.close().map_err(|_| "failed to close SD volume")?;

        Ok(file_contents)
    })
}

fn overwrite_file_contents(file_name: &str, file_contents: &[u8]) -> Result<(), &'static str> {
    with_sd_storage_mut(|sd_storage| {
        let volume = sd_storage
            .volume_manager
            .open_volume(VolumeIdx(0))
            .map_err(|_| "failed to open SD volume")?;
        let root_directory = volume
            .open_root_dir()
            .map_err(|_| "failed to open SD root directory")?;

        let file = root_directory
            .open_file_in_dir(file_name, Mode::ReadWriteCreateOrTruncate)
            .map_err(|_| "failed to open target file for upload")?;
        file.write(file_contents)
            .map_err(|_| "failed to write uploaded file contents")?;
        file.flush()
            .map_err(|_| "failed to flush uploaded file contents")?;
        file.close()
            .map_err(|_| "failed to close uploaded file")?;

        root_directory
            .close()
            .map_err(|_| "failed to close SD root directory")?;
        volume.close().map_err(|_| "failed to close SD volume")?;

        Ok(())
    })
}

fn build_system_device_status_cloud_event_json<const BUFFER_SIZE: usize>(
    uptime_seconds: u64,
) -> Result<HeaplessString<BUFFER_SIZE>, &'static str> {
    use core::fmt::Write;

    let mut cloud_event_json = HeaplessString::<BUFFER_SIZE>::new();

    write!(
        cloud_event_json,
        "{{\"specversion\":\"1.0\",\"id\":\"system-device-status-{}\",\"source\":\"{}\",\"type\":\"{}\",\"datacontenttype\":\"application/json\",\"time\":\"2026-04-03T17:18:43Z\",\"data\":{{\"device\":{{\"chip_id\":0,\"chip_model\":\"ESP32-S3\",\"chip_cores\":2,\"chip_revision\":0,\"efuse_mac\":\"0\"}},\"network\":{{\"ipv4_address\":\"0.0.0.0\",\"wifi_rssi\":0}},\"runtime\":{{\"uptime\":\"{}s\",\"uptime_seconds\":{},\"memory_heap_bytes\":0}},\"storage\":{{\"location\":\"sd\",\"total_bytes\":0,\"used_bytes\":0,\"free_bytes\":0}}}}}}",
        uptime_seconds,
        SYSTEM_DEVICE_STATUS_SOURCE,
        SYSTEM_DEVICE_STATUS_TYPE,
        uptime_seconds,
        uptime_seconds
    )
    .map_err(|_| "system status JSON buffer too small")?;

    Ok(cloud_event_json)
}

async fn select_i2c_mux_channel(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
    mux_channel: u8,
) -> Result<(), &'static str> {
    if mux_channel > 7 {
        return Err("mux channel out of range");
    }

    let mux_channel_mask = 1_u8 << mux_channel;
    i2c_bus
        .write_async(I2C_MUX_ADDRESS, &[mux_channel_mask])
        .await
        .map_err(|_| "failed to select I2C mux channel")?;
    Ok(())
}

async fn discover_temperature_humidity_sensor_address(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
) -> Option<u8> {
    for sensor_candidate_address in SENSOR_CANDIDATE_ADDRESSES {
        if i2c_bus
            .write_async(sensor_candidate_address, &[])
            .await
            .is_ok()
        {
            return Some(sensor_candidate_address);
        }
    }

    None
}

fn calculate_crc8(data_bytes: &[u8]) -> u8 {
    let mut crc_value: u8 = 0xFF;

    for data_byte in data_bytes {
        crc_value ^= *data_byte;
        for _ in 0..8 {
            crc_value = if (crc_value & 0x80) != 0 {
                (crc_value << 1) ^ 0x31
            } else {
                crc_value << 1
            };
        }
    }

    crc_value
}

fn convert_temperature_celsius(temperature_raw_value: u16) -> f32 {
    -45.0 + 175.0 * (temperature_raw_value as f32 / 65535.0)
}

fn convert_relative_humidity_percent(humidity_raw_value: u16) -> f32 {
    100.0 * (humidity_raw_value as f32 / 65535.0)
}

async fn read_temperature_humidity_once(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
    sensor_address: u8,
) -> Result<(f32, f32), &'static str> {
    i2c_bus
        .write_async(sensor_address, &SENSOR_MEASUREMENT_COMMAND)
        .await
        .map_err(|_| "failed to send measurement command")?;

    Timer::after(Duration::from_millis(60)).await;

    let mut measurement_buffer = [0_u8; 6];
    i2c_bus
        .read_async(sensor_address, &mut measurement_buffer)
        .await
        .map_err(|_| "failed to read measurement bytes")?;

    let temperature_bytes = [measurement_buffer[0], measurement_buffer[1]];
    let humidity_bytes = [measurement_buffer[3], measurement_buffer[4]];
    let received_temperature_crc = measurement_buffer[2];
    let received_humidity_crc = measurement_buffer[5];

    if received_temperature_crc != calculate_crc8(&temperature_bytes) {
        return Err("temperature CRC mismatch");
    }
    if received_humidity_crc != calculate_crc8(&humidity_bytes) {
        return Err("humidity CRC mismatch");
    }

    let temperature_raw_value = u16::from_be_bytes(temperature_bytes);
    let humidity_raw_value = u16::from_be_bytes(humidity_bytes);

    Ok((
        convert_temperature_celsius(temperature_raw_value),
        convert_relative_humidity_percent(humidity_raw_value),
    ))
}

struct FilesystemListService;

impl picoserve::routing::RequestHandlerService<(), ()> for FilesystemListService {
    async fn call_request_handler_service<
        R: picoserve::io::Read,
        W: picoserve::response::ResponseWriter<Error = R::Error>,
    >(
        &self,
        _state: &(),
        (): (),
        request: picoserve::request::Request<'_, R>,
        response_writer: W,
    ) -> Result<picoserve::ResponseSent, W::Error> {
        match build_filesystem_list_json_response::<2304>() {
            Ok(filesystem_list_json) => (
                StatusCode::OK,
                ("Content-Type", "application/json; charset=utf-8"),
                format_args!("{}", filesystem_list_json),
            )
                .write_to(request.body_connection.finalize().await?, response_writer)
                .await,
            Err(error_message) => match build_json_error_response::<256>(
                "FILESYSTEM_LIST_FAILED",
                error_message,
            ) {
                Ok(error_json) => (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    ("Content-Type", "application/json; charset=utf-8"),
                    format_args!("{}", error_json),
                )
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await,
                Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, "FILESYSTEM_LIST_FAILED")
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await,
            },
        }
    }
}

struct SystemDeviceStatusService;

impl picoserve::routing::RequestHandlerService<(), ()> for SystemDeviceStatusService {
    async fn call_request_handler_service<
        R: picoserve::io::Read,
        W: picoserve::response::ResponseWriter<Error = R::Error>,
    >(
        &self,
        _state: &(),
        (): (),
        request: picoserve::request::Request<'_, R>,
        response_writer: W,
    ) -> Result<picoserve::ResponseSent, W::Error> {
        match build_system_device_status_cloud_event_json::<1024>(Instant::now().as_secs()) {
            Ok(status_json) => (
                StatusCode::OK,
                ("Content-Type", "application/json; charset=utf-8"),
                format_args!("{}", status_json),
            )
                .write_to(request.body_connection.finalize().await?, response_writer)
                .await,
            Err(error_message) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                ("Content-Type", "text/plain; charset=utf-8"),
                error_message,
            )
                .write_to(request.body_connection.finalize().await?, response_writer)
                .await,
        }
    }
}

struct FileDownloadService;

impl picoserve::routing::RequestHandlerService<(), (AllocString,)> for FileDownloadService {
    async fn call_request_handler_service<
        R: picoserve::io::Read,
        W: picoserve::response::ResponseWriter<Error = R::Error>,
    >(
        &self,
        _state: &(),
        (file_name,): (AllocString,),
        request: picoserve::request::Request<'_, R>,
        response_writer: W,
    ) -> Result<picoserve::ResponseSent, W::Error> {
        if !is_supported_flat_file_name(&file_name) {
            return match build_json_error_response::<256>("INVALID_PATH", "invalid file path") {
                Ok(error_json) => (
                    StatusCode::BAD_REQUEST,
                    ("Content-Type", "application/json; charset=utf-8"),
                    format_args!("{}", error_json),
                )
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await,
                Err(_) => (StatusCode::BAD_REQUEST, "INVALID_PATH")
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await,
            };
        }

        match read_file_contents::<8192>(&file_name) {
            Ok(file_contents) => match core::str::from_utf8(file_contents.as_slice()) {
                Ok(file_text) => (
                    StatusCode::OK,
                    ("Content-Type", "text/csv; charset=utf-8"),
                    format_args!("{}", file_text),
                )
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await,
                Err(_) => {
                    match build_json_error_response::<256>(
                        "FILE_UTF8_DECODE_FAILED",
                        "file is not valid UTF-8 text",
                    ) {
                        Ok(error_json) => (
                            StatusCode::INTERNAL_SERVER_ERROR,
                            ("Content-Type", "application/json; charset=utf-8"),
                            format_args!("{}", error_json),
                        )
                            .write_to(request.body_connection.finalize().await?, response_writer)
                            .await,
                        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, "FILE_UTF8_DECODE_FAILED")
                            .write_to(request.body_connection.finalize().await?, response_writer)
                            .await,
                    }
                }
            },
            Err(error_message) => {
                if error_message == "failed to open requested file" {
                    match build_json_error_response::<256>("NOT_FOUND", "file not found") {
                        Ok(error_json) => (
                            StatusCode::NOT_FOUND,
                            ("Content-Type", "application/json; charset=utf-8"),
                            format_args!("{}", error_json),
                        )
                            .write_to(request.body_connection.finalize().await?, response_writer)
                            .await,
                        Err(_) => (StatusCode::NOT_FOUND, "NOT_FOUND")
                            .write_to(request.body_connection.finalize().await?, response_writer)
                            .await,
                    }
                } else {
                    match build_json_error_response::<256>("FILE_READ_FAILED", error_message) {
                        Ok(error_json) => (
                            StatusCode::INTERNAL_SERVER_ERROR,
                            ("Content-Type", "application/json; charset=utf-8"),
                            format_args!("{}", error_json),
                        )
                            .write_to(request.body_connection.finalize().await?, response_writer)
                            .await,
                        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, "FILE_READ_FAILED")
                            .write_to(request.body_connection.finalize().await?, response_writer)
                            .await,
                    }
                }
            }
        }
    }
}

struct FileUploadService;

impl picoserve::routing::RequestHandlerService<(), (AllocString,)> for FileUploadService {
    async fn call_request_handler_service<
        R: picoserve::io::Read,
        W: picoserve::response::ResponseWriter<Error = R::Error>,
    >(
        &self,
        _state: &(),
        (file_name,): (AllocString,),
        mut request: picoserve::request::Request<'_, R>,
        response_writer: W,
    ) -> Result<picoserve::ResponseSent, W::Error> {
        if !is_supported_flat_file_name(&file_name) {
            return match build_json_error_response::<256>("INVALID_PATH", "invalid file path") {
                Ok(error_json) => (
                    StatusCode::BAD_REQUEST,
                    ("Content-Type", "application/json; charset=utf-8"),
                    format_args!("{}", error_json),
                )
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await,
                Err(_) => (StatusCode::BAD_REQUEST, "INVALID_PATH")
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await,
            };
        }

        if request.body_connection.content_length() > FILE_UPLOAD_MAX_BYTES {
            return match build_json_error_response::<256>(
                "UPLOAD_TOO_LARGE",
                "uploaded file exceeds maximum allowed size",
            ) {
                Ok(error_json) => (
                    StatusCode::PAYLOAD_TOO_LARGE,
                    ("Content-Type", "application/json; charset=utf-8"),
                    format_args!("{}", error_json),
                )
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await,
                Err(_) => (StatusCode::PAYLOAD_TOO_LARGE, "UPLOAD_TOO_LARGE")
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await,
            };
        }

        use picoserve::io::Read;

        let mut request_body_reader = request.body_connection.body().reader();
        let mut read_chunk_buffer = [0u8; 256];
        let mut uploaded_file_contents = HeaplessVec::<u8, FILE_UPLOAD_MAX_BYTES>::new();

        loop {
            let read_byte_count = request_body_reader.read(&mut read_chunk_buffer).await?;
            if read_byte_count == 0 {
                break;
            }

            for &read_byte in &read_chunk_buffer[..read_byte_count] {
                if uploaded_file_contents.push(read_byte).is_err() {
                    return match build_json_error_response::<256>(
                        "UPLOAD_TOO_LARGE",
                        "uploaded file exceeds maximum allowed size",
                    ) {
                        Ok(error_json) => (
                            StatusCode::PAYLOAD_TOO_LARGE,
                            ("Content-Type", "application/json; charset=utf-8"),
                            format_args!("{}", error_json),
                        )
                            .write_to(request.body_connection.finalize().await?, response_writer)
                            .await,
                        Err(_) => (StatusCode::PAYLOAD_TOO_LARGE, "UPLOAD_TOO_LARGE")
                            .write_to(request.body_connection.finalize().await?, response_writer)
                            .await,
                    };
                }
            }
        }

        match overwrite_file_contents(&file_name, uploaded_file_contents.as_slice()) {
            Ok(()) => {
                let mut upload_success_json = HeaplessString::<256>::new();
                use core::fmt::Write;
                let _ = write!(
                    upload_success_json,
                    "{{\"ok\":true,\"data\":{{\"name\":\"{}\",\"size\":{}}}}}",
                    file_name,
                    uploaded_file_contents.len()
                );
                (
                    StatusCode::OK,
                    ("Content-Type", "application/json; charset=utf-8"),
                    format_args!("{}", upload_success_json),
                )
                    .write_to(request.body_connection.finalize().await?, response_writer)
                    .await
            }
            Err(error_message) => {
                match build_json_error_response::<256>("UPLOAD_WRITE_FAILED", error_message) {
                    Ok(error_json) => (
                        StatusCode::INTERNAL_SERVER_ERROR,
                        ("Content-Type", "application/json; charset=utf-8"),
                        format_args!("{}", error_json),
                    )
                        .write_to(request.body_connection.finalize().await?, response_writer)
                        .await,
                    Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, "UPLOAD_WRITE_FAILED")
                        .write_to(request.body_connection.finalize().await?, response_writer)
                        .await,
                }
            }
        }
    }
}

fn filesystem_router() -> picoserve::Router<impl picoserve::routing::PathRouter> {
    picoserve::Router::new()
        .route("/list", get_service(FilesystemListService))
        .route(
            ("/file", parse_path_segment::<AllocString>()),
            get_service(FileDownloadService).post_service(FileUploadService),
        )
}

fn system_router() -> picoserve::Router<impl picoserve::routing::PathRouter> {
    picoserve::Router::new().route("/device/status", get_service(SystemDeviceStatusService))
}

fn api_router() -> picoserve::Router<impl picoserve::routing::PathRouter> {
    picoserve::Router::new()
        .nest("/filesystem", filesystem_router())
        .nest("/system", system_router())
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
async fn temperature_humidity_logger_task(mut i2c_bus: I2c<'static, esp_hal::Async>) {
    use core::fmt::Write;

    let mut sampling_interval = Ticker::every(Duration::from_secs(5));
    let mut discovered_sensor_address: Option<u8> = None;

    loop {
        sampling_interval.next().await;

        if let Err(error_message) = select_i2c_mux_channel(&mut i2c_bus, TEMPERATURE_HUMIDITY_MUX_CHANNEL).await {
            info!("failed to select I2C mux channel {}: {}", TEMPERATURE_HUMIDITY_MUX_CHANNEL, error_message);
            continue;
        }

        if discovered_sensor_address.is_none() {
            discovered_sensor_address =
                discover_temperature_humidity_sensor_address(&mut i2c_bus).await;
            if let Some(sensor_address) = discovered_sensor_address {
                info!(
                    "temperature/humidity sensor found on mux channel {} at I2C address {:#04x}",
                    TEMPERATURE_HUMIDITY_MUX_CHANNEL,
                    sensor_address
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

        match read_temperature_humidity_once(&mut i2c_bus, sensor_address).await {
            Ok((temperature_celsius, relative_humidity_percent)) => {
                let timestamp_millis = Instant::now().as_millis();
                let mut data_csv_line = HeaplessString::<192>::new();

                if write!(
                    data_csv_line,
                    "{},{:.2},{:.2},,,,,,,,\n",
                    timestamp_millis,
                    temperature_celsius,
                    relative_humidity_percent
                )
                .is_err()
                {
                    info!("failed to format data.csv row");
                    continue;
                }

                if let Err(error_message) = append_data_csv_line(data_csv_line.as_str()) {
                    info!("failed to append data.csv row: {}", error_message);
                } else {
                    info!(
                        "logged temp/humidity sample: temperature={}C humidity={}%%",
                        temperature_celsius,
                        relative_humidity_percent
                    );
                }
            }
            Err(error_message) => {
                info!(
                    "failed to read temp/humidity sensor on mux channel {}: {}",
                    TEMPERATURE_HUMIDITY_MUX_CHANNEL,
                    error_message
                );
            }
        }
    }
}

#[embassy_executor::task]
async fn http_server_task(stack: Stack<'static>) {
    let app = picoserve::Router::new()
        .nest("/api", api_router())
        .route(
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

    let _sensor_power_relay =
        Output::new(peripherals.GPIO5, Level::High, OutputConfig::default());
    Delay::new().delay_millis(1_000);

    initialize_sd_storage(
        peripherals.SPI2,
        peripherals.GPIO10,
        peripherals.GPIO11,
        peripherals.GPIO12,
        peripherals.GPIO13,
    );
    if let Err(error_message) = ensure_data_csv_exists() {
        info!("failed to initialize data.csv: {}", error_message);
    }

    let temperature_humidity_i2c_bus = I2c::new(
        peripherals.I2C0,
        I2cConfig::default().with_frequency(Rate::from_khz(I2C_BUS_FREQUENCY_KHZ)),
    )
    .unwrap()
    .with_sda(peripherals.GPIO8)
    .with_scl(peripherals.GPIO9)
    .into_async();

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
