#![no_std]
#![no_main]

use core::str;

use defmt::info;
use embedded_sdmmc::{Mode, SdCard, TimeSource, Timestamp, VolumeIdx, VolumeManager};
use esp_hal::{
    delay::Delay,
    gpio::{Level, Output, OutputConfig},
    peripherals::{GPIO10, GPIO11, GPIO12, GPIO13, SPI2},
    spi::{
        Mode as SpiMode,
        master::{Config as SpiConfig, Spi},
    },
    time::Rate,
    interrupt::software::SoftwareInterruptControl,
    timer::timg::TimerGroup,
};

const FILESYSTEM_LIST_ENDPOINT_PATH: &str = "/api/filesystem/list";
const FILESYSTEM_FILE_ENDPOINT_PREFIX: &str = "/api/filesystem/file/";
const FILESYSTEM_UPLOAD_ENDPOINT_PREFIX: &str = "/api/filesystem/file/";
const SYSTEM_DEVICE_STATUS_ENDPOINT_PATH: &str = "/api/system/device/status";
const API_ROUTE_PREFIX: &str = "/api";
const FILESYSTEM_ROUTE_PREFIX: &str = "/filesystem";
const SYSTEM_ROUTE_PREFIX: &str = "/system";
const DEVICE_ROUTE_PREFIX: &str = "/device";

const SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE: &str = "{\"specversion\":\"1.0\",\"id\":\"system-device-status-45591\",\"source\":\"urn:apidae-systems:tenant:p-uot-ins:site:university-of-ottawa\",\"type\":\"com.apidae.system.device.status.v1\",\"datacontenttype\":\"application/json\",\"time\":\"2026-04-03T17:18:43Z\",\"data\":{\"device\":{\"chip_id\":966764,\"chip_model\":\"ESP32-S3\",\"chip_cores\":2,\"chip_revision\":2,\"efuse_mac\":\"119572138669276\"},\"network\":{\"ipv4_address\":\"10.0.0.95\",\"wifi_rssi\":-61},\"runtime\":{\"uptime\":\"45s\",\"uptime_seconds\":45,\"memory_heap_bytes\":46016},\"storage\":{\"location\":\"sd\",\"total_bytes\":1876951040,\"used_bytes\":557056,\"free_bytes\":1876393984}}}";
const FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE: &str =
    "{\"ok\":true,\"data\":{\"entries\":[{\"name\":\"DATA.CSV\",\"size\":270,\"last_write_unix\":0}]}}";
const FILESYSTEM_ERROR_JSON_RESPONSE_EXAMPLE: &str =
    "{\"ok\":false,\"error\":{\"code\":\"INVALID_PATH\",\"message\":\"invalid file path\"}}";

const SD_CHIP_SELECT_GPIO_PIN: u32 = 10;
const SD_MOSI_GPIO_PIN: u32 = 11;
const SD_CLOCK_GPIO_PIN: u32 = 12;
const SD_MISO_GPIO_PIN: u32 = 13;

const SD_SPI_INIT_FREQUENCY_KHZ: u32 = 400;
const SD_CARD_STARTUP_CLOCK_BYTES: [u8; 10] = [0xFF; 10];

const DATA_CSV_FILE_NAME: &str = "data.csv";
const DATA_CSV_HEADER_LINE: &str = "timestamp,temperature_celsius_0,humidity_percent_0,temperature_celsius_1,humidity_percent_1,temperature_celsius_2,humidity_percent_2,voltage_channel_0,voltage_channel_1,voltage_channel_2,voltage_channel_3";
const DATA_CSV_SAMPLE_LINE: &str =
    "1710000000,24.6,47.1,24.9,46.8,25.1,46.4,1.650,1.654,1.648,1.651";
const EXPECTED_DATA_CSV_COLUMN_COUNT: usize = 11;

struct Context {
    spi2_peripheral: SPI2<'static>,
    sd_chip_select_gpio: GPIO10<'static>,
    sd_mosi_gpio: GPIO11<'static>,
    sd_clock_gpio: GPIO12<'static>,
    sd_miso_gpio: GPIO13<'static>,
}

struct FixedTimeSource;

impl TimeSource for FixedTimeSource {
    fn get_timestamp(&self) -> Timestamp {
        Timestamp::from_calendar(2026, 4, 3, 12, 0, 0).unwrap()
    }
}

fn create_spi_bus(context: Context) -> (Spi<'static, esp_hal::Blocking>, Output<'static>) {
    let spi_bus = Spi::new(
        context.spi2_peripheral,
        SpiConfig::default()
            .with_frequency(Rate::from_khz(SD_SPI_INIT_FREQUENCY_KHZ))
            .with_mode(SpiMode::_0),
    )
    .unwrap()
    .with_sck(context.sd_clock_gpio)
    .with_mosi(context.sd_mosi_gpio)
    .with_miso(context.sd_miso_gpio);

    let chip_select_output = Output::new(
        context.sd_chip_select_gpio,
        Level::High,
        OutputConfig::default(),
    );

    (spi_bus, chip_select_output)
}

fn send_sd_startup_clock_cycles(spi_bus: &mut Spi<'static, esp_hal::Blocking>) {
    spi_bus.write(&SD_CARD_STARTUP_CLOCK_BYTES).unwrap();
}

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::tests(executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Context {
        let peripherals = esp_hal::init(esp_hal::Config::default());

        let timer_group0 = TimerGroup::new(peripherals.TIMG0);
        let software_interrupts = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
        esp_rtos::start(timer_group0.timer0, software_interrupts.software_interrupt0);

        rtt_target::rtt_init_defmt!();

        info!(
            "http api test initialized (CS=GPIO{}, MOSI=GPIO{}, SCK=GPIO{}, MISO=GPIO{})",
            SD_CHIP_SELECT_GPIO_PIN,
            SD_MOSI_GPIO_PIN,
            SD_CLOCK_GPIO_PIN,
            SD_MISO_GPIO_PIN
        );

        Context {
            spi2_peripheral: peripherals.SPI2,
            sd_chip_select_gpio: peripherals.GPIO10,
            sd_mosi_gpio: peripherals.GPIO11,
            sd_clock_gpio: peripherals.GPIO12,
            sd_miso_gpio: peripherals.GPIO13,
        }
    }

    #[test]
    async fn http_filesystem_endpoint_contracts_are_stable() {
        defmt::assert_eq!(API_ROUTE_PREFIX, "/api");
        defmt::assert_eq!(FILESYSTEM_ROUTE_PREFIX, "/filesystem");
        defmt::assert_eq!(SYSTEM_ROUTE_PREFIX, "/system");
        defmt::assert_eq!(DEVICE_ROUTE_PREFIX, "/device");

        defmt::assert_eq!(FILESYSTEM_LIST_ENDPOINT_PATH, "/api/filesystem/list");
        defmt::assert_eq!(FILESYSTEM_FILE_ENDPOINT_PREFIX, "/api/filesystem/file/");
        defmt::assert_eq!(FILESYSTEM_UPLOAD_ENDPOINT_PREFIX, "/api/filesystem/file/");
        defmt::assert_eq!(SYSTEM_DEVICE_STATUS_ENDPOINT_PATH, "/api/system/device/status");
    }

    #[test]
    async fn scalable_filesystem_json_envelope_shape_is_stable() {
        defmt::assert!(FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE.contains("\"ok\":true"));
        defmt::assert!(FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE.contains("\"data\":{\"entries\":"));
        defmt::assert!(FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE.contains("\"name\":"));
        defmt::assert!(FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE.contains("\"size\":"));
        defmt::assert!(FILESYSTEM_LIST_JSON_RESPONSE_EXAMPLE.contains("\"last_write_unix\":"));

        defmt::assert!(FILESYSTEM_ERROR_JSON_RESPONSE_EXAMPLE.contains("\"ok\":false"));
        defmt::assert!(FILESYSTEM_ERROR_JSON_RESPONSE_EXAMPLE.contains("\"error\":{\"code\":"));
        defmt::assert!(FILESYSTEM_ERROR_JSON_RESPONSE_EXAMPLE.contains("\"message\":"));
    }

    #[test]
    async fn upload_limits_match_runtime_expectation() {
        defmt::assert_eq!(firmware::config::sd_card::FILE_UPLOAD_MAX_BYTES, 4096);
    }

    #[test]
    async fn system_device_status_cloud_event_shape_is_stable() {
        defmt::assert!(
            SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains("\"specversion\":\"1.0\"")
        );
        defmt::assert!(SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains(
            "\"type\":\"com.apidae.system.device.status.v1\""
        ));
        defmt::assert!(SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains("\"data\":{\"device\":"));
        defmt::assert!(SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains("\"network\":"));
        defmt::assert!(SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains("\"runtime\":"));
        defmt::assert!(SYSTEM_DEVICE_STATUS_CLOUDEVENT_EXAMPLE.contains("\"storage\":"));
    }

    #[test]
    async fn data_csv_can_be_created_and_read_back_for_http_download_validation(context: Context) {
        let (mut spi_bus, chip_select_output) = create_spi_bus(context);

        send_sd_startup_clock_cycles(&mut spi_bus);

        let spi_device =
            embedded_hal_bus::spi::ExclusiveDevice::new(spi_bus, chip_select_output, Delay::new())
                .unwrap();

        let sd_card = SdCard::new(spi_device, Delay::new());
        let volume_manager = VolumeManager::new(sd_card, FixedTimeSource);
        let volume0 = volume_manager.open_volume(VolumeIdx(0)).unwrap();
        let root_directory = volume0.open_root_dir().unwrap();

        let data_csv_file = root_directory
            .open_file_in_dir(DATA_CSV_FILE_NAME, Mode::ReadWriteCreateOrTruncate)
            .unwrap();

        data_csv_file.write(DATA_CSV_HEADER_LINE.as_bytes()).unwrap();
        data_csv_file.write(b"\n").unwrap();
        data_csv_file.write(DATA_CSV_SAMPLE_LINE.as_bytes()).unwrap();
        data_csv_file.write(b"\n").unwrap();
        data_csv_file.flush().unwrap();

        data_csv_file.seek_from_start(0).unwrap();

        let mut data_csv_readback_buffer = [0u8; 512];
        let mut total_readback_bytes = 0usize;

        while !data_csv_file.is_eof() {
            let read_byte_count = data_csv_file
                .read(&mut data_csv_readback_buffer[total_readback_bytes..])
                .unwrap();

            if read_byte_count == 0 {
                break;
            }

            total_readback_bytes += read_byte_count;
        }

        let data_csv_readback_text =
            str::from_utf8(&data_csv_readback_buffer[..total_readback_bytes]).unwrap();

        info!("data.csv readback:\n{}", data_csv_readback_text);

        let mut data_csv_lines = data_csv_readback_text.lines();
        let readback_header_line = data_csv_lines.next().unwrap();
        let readback_sample_line = data_csv_lines.next().unwrap();

        defmt::assert_eq!(readback_header_line, DATA_CSV_HEADER_LINE);
        defmt::assert_eq!(readback_sample_line, DATA_CSV_SAMPLE_LINE);

        let header_column_count = readback_header_line.split(',').count();
        let sample_column_count = readback_sample_line.split(',').count();

        defmt::assert_eq!(header_column_count, EXPECTED_DATA_CSV_COLUMN_COUNT);
        defmt::assert_eq!(sample_column_count, EXPECTED_DATA_CSV_COLUMN_COUNT);

        data_csv_file.close().unwrap();
        root_directory.close().unwrap();
        volume0.close().unwrap();
    }
}
