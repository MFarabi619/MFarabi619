use core::fmt::Write;

use defmt::info;
use embedded_sdmmc::{Mode, SdCard, TimeSource, Timestamp, VolumeIdx, VolumeManager};
use esp_hal::{
    delay::Delay,
    gpio::{Level, Output, OutputConfig},
    peripherals::{GPIO10, GPIO11, GPIO12, GPIO13, SPI2},
    spi::{
        master::{Config as SpiConfig, Spi},
        Mode as SpiMode,
    },
    time::Rate,
};
use heapless::{String as HeaplessString, Vec as HeaplessVec};

use crate::modules::api_types::FilesystemEntryPayload;

pub const SD_CHIP_SELECT_GPIO_PIN: u32 = 10;
pub const SD_MOSI_GPIO_PIN: u32 = 11;
pub const SD_SPI_CLOCK_GPIO_PIN: u32 = 12;
pub const SD_MISO_GPIO_PIN: u32 = 13;
pub const SD_SPI_INIT_FREQUENCY_KHZ: u32 = 400;
pub const SD_CARD_STARTUP_CLOCK_BYTES: [u8; 10] = [0xFF; 10];

pub const DATA_CSV_FILE_NAME: &str = "data.csv";
pub const DATA_CSV_HEADER_LINE: &str = "timestamp,temperature_celcius_0,humidity_percent_0,temperature_celcius_1,humidity_percent_1,temperature_celcius_2,humidity_percent_2,voltage_channel_0,voltage_channel_1,voltage_channel_2,voltage_channel_3";

pub const FILE_UPLOAD_MAX_BYTES: usize = 4096;

type SdSpiBus = Spi<'static, esp_hal::Blocking>;
type SdChipSelectOutput = Output<'static>;
type SdSpiDevice = embedded_hal_bus::spi::ExclusiveDevice<SdSpiBus, SdChipSelectOutput, Delay>;
type SdCardDevice = SdCard<SdSpiDevice, Delay>;
type SdVolumeManager = VolumeManager<SdCardDevice, FixedTimeSource>;

struct SdStorage {
    volume_manager: SdVolumeManager,
}

#[derive(Default)]
pub struct FixedTimeSource;

impl TimeSource for FixedTimeSource {
    fn get_timestamp(&self) -> Timestamp {
        Timestamp::from_calendar(2026, 4, 3, 12, 0, 0).unwrap()
    }
}

static SD_STORAGE: critical_section::Mutex<core::cell::RefCell<Option<SdStorage>>> =
    critical_section::Mutex::new(core::cell::RefCell::new(None));

pub fn initialize(
    sd_spi_peripheral: SPI2<'static>,
    sd_chip_select_gpio: GPIO10<'static>,
    sd_mosi_gpio: GPIO11<'static>,
    sd_spi_clock_gpio: GPIO12<'static>,
    sd_miso_gpio: GPIO13<'static>,
) {
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

    let sd_chip_select_output =
        Output::new(sd_chip_select_gpio, Level::High, OutputConfig::default());

    let sd_spi_device = embedded_hal_bus::spi::ExclusiveDevice::new(
        sd_spi_bus,
        sd_chip_select_output,
        Delay::new(),
    )
    .unwrap();
    let sd_card = SdCard::new(sd_spi_device, Delay::new());

    if let Ok(sd_card_capacity_bytes) = sd_card.num_bytes() {
        info!(
            "SD card detected (CS=GPIO{}, MOSI=GPIO{}, SCK=GPIO{}, MISO=GPIO{}, size={} MiB)",
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
        let sd_storage = sd_storage_option
            .as_mut()
            .ok_or("SD storage not initialized")?;
        operation(sd_storage)
    })
}

pub fn ensure_data_csv_exists() -> Result<(), &'static str> {
    with_sd_storage_mut(|sd_storage| {
        let volume = sd_storage
            .volume_manager
            .open_volume(VolumeIdx(0))
            .map_err(|_| "failed to open SD volume")?;
        let root_directory = volume
            .open_root_dir()
            .map_err(|_| "failed to open SD root directory")?;

        if let Ok(existing_data_csv_file) =
            root_directory.open_file_in_dir(DATA_CSV_FILE_NAME, Mode::ReadOnly)
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

pub fn append_data_csv_line(data_csv_line: &str) -> Result<(), &'static str> {
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

pub fn list_filesystem_entries() -> Result<HeaplessVec<FilesystemEntryPayload, 64>, &'static str> {
    with_sd_storage_mut(|sd_storage| {
        let volume = sd_storage
            .volume_manager
            .open_volume(VolumeIdx(0))
            .map_err(|_| "failed to open SD volume")?;
        let root_directory = volume
            .open_root_dir()
            .map_err(|_| "failed to open SD root directory")?;

        let mut filesystem_entries = HeaplessVec::<FilesystemEntryPayload, 64>::new();

        root_directory
            .iterate_dir(|directory_entry| {
                if directory_entry.attributes.is_directory() {
                    return;
                }

                let mut file_name = HeaplessString::<32>::new();
                if write!(file_name, "{}", directory_entry.name).is_err() {
                    return;
                }

                let _ = filesystem_entries.push(FilesystemEntryPayload {
                    name: file_name,
                    size: directory_entry.size,
                    last_write_unix: 0,
                });
            })
            .map_err(|_| "failed to iterate SD root directory")?;

        root_directory
            .close()
            .map_err(|_| "failed to close SD root directory")?;
        volume.close().map_err(|_| "failed to close SD volume")?;
        Ok(filesystem_entries)
    })
}

pub fn is_supported_flat_file_name(file_name: &str) -> bool {
    !file_name.is_empty()
        && !file_name.contains('/')
        && !file_name.contains('\\')
        && !file_name.contains("..")
}

pub fn read_file_contents<const BUFFER_SIZE: usize>(
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

pub fn overwrite_file_contents(file_name: &str, file_contents: &[u8]) -> Result<(), &'static str> {
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
        file.close().map_err(|_| "failed to close uploaded file")?;

        root_directory
            .close()
            .map_err(|_| "failed to close SD root directory")?;
        volume.close().map_err(|_| "failed to close SD volume")?;

        Ok(())
    })
}
