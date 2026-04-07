use core::fmt::Write;

use defmt::info;
use embassy_sync::blocking_mutex::raw::NoopRawMutex;
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

use crate::config::sd_card;

const STARTUP_CLOCK_BYTES: [u8; 10] = [0xFF; 10];
const MAX_FILENAME_LEN: usize = 32;
const MAX_FS_ENTRIES: usize = 64;

/// Fallback timestamp returned by `SntpTimeSource` when SNTP has not yet
/// synced — chosen as a recent date so FAT entries don't appear from 1980.
const FALLBACK_YEAR: u16 = 2026;
const FALLBACK_MONTH: u8 = 1;
const FALLBACK_DAY: u8 = 1;

#[derive(serde::Serialize)]
pub struct FilesystemEntryPayload {
    pub name: HeaplessString<MAX_FILENAME_LEN>,
    pub size: u32,
    pub last_write_unix: u64,
    pub is_directory: bool,
}

#[derive(Debug, Clone, Copy, defmt::Format)]
pub enum SdError {
    NotInitialized,
    VolumeFailed,
    RootDirFailed,
    NavigationFailed,
    FileNotFound,
    CreateFailed,
    ReadFailed,
    WriteFailed,
    FlushFailed,
    DeleteFailed,
    DirectoryFailed,
    SeekFailed,
}

impl core::fmt::Display for SdError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            SdError::NotInitialized => write!(f, "SD storage not initialized"),
            SdError::VolumeFailed => write!(f, "failed to open volume"),
            SdError::RootDirFailed => write!(f, "failed to open root directory"),
            SdError::NavigationFailed => write!(f, "directory not found"),
            SdError::FileNotFound => write!(f, "file not found"),
            SdError::CreateFailed => write!(f, "failed to create file"),
            SdError::ReadFailed => write!(f, "failed to read"),
            SdError::WriteFailed => write!(f, "failed to write"),
            SdError::FlushFailed => write!(f, "failed to flush"),
            SdError::DeleteFailed => write!(f, "failed to delete"),
            SdError::DirectoryFailed => write!(f, "failed to create directory"),
            SdError::SeekFailed => write!(f, "failed to seek"),
        }
    }
}

type SdSpiBus = Spi<'static, esp_hal::Blocking>;
type SdChipSelectOutput = Output<'static>;
type SdSpiDevice = embedded_hal_bus::spi::ExclusiveDevice<SdSpiBus, SdChipSelectOutput, Delay>;
type SdCardDevice = SdCard<SdSpiDevice, Delay>;
type SdVm = VolumeManager<SdCardDevice, SntpTimeSource>;
type SdDir<'a> = embedded_sdmmc::Directory<'a, SdCardDevice, SntpTimeSource, 4, 4, 1>;

struct SdStorageCell(
    embassy_sync::blocking_mutex::Mutex<NoopRawMutex, core::cell::RefCell<Option<SdVm>>>,
);
// SAFETY: Single-threaded embassy executor. NoopRawMutex is !Sync as a
// conservative guard for multi-threaded contexts that don't apply here.
unsafe impl Sync for SdStorageCell {}

#[derive(Default)]
pub struct SntpTimeSource;

fn fallback_timestamp() -> Timestamp {
    Timestamp::from_calendar(FALLBACK_YEAR, FALLBACK_MONTH, FALLBACK_DAY, 0, 0, 0)
        .expect("fallback date constants are valid")
}

impl TimeSource for SntpTimeSource {
    fn get_timestamp(&self) -> Timestamp {
        let epoch = crate::time::get_current_epoch_secs();
        if epoch == 0 {
            return fallback_timestamp();
        }
        let calendar = crate::time::epoch_to_calendar(epoch);
        Timestamp::from_calendar(
            calendar.year,
            calendar.month,
            calendar.day,
            calendar.hours,
            calendar.minutes,
            calendar.seconds,
        )
        .unwrap_or_else(|_| fallback_timestamp())
    }
}

static SD_STORAGE: SdStorageCell = SdStorageCell(
    embassy_sync::blocking_mutex::Mutex::new(core::cell::RefCell::new(None)),
);

/// Returns the SD card capacity in MiB, or 0 if detection failed.
pub fn initialize(
    sd_spi_peripheral: SPI2<'static>,
    sd_chip_select_gpio: GPIO10<'static>,
    sd_mosi_gpio: GPIO11<'static>,
    sd_spi_clock_gpio: GPIO12<'static>,
    sd_miso_gpio: GPIO13<'static>,
) -> u32 {
    let mut sd_spi_bus = Spi::new(
        sd_spi_peripheral,
        SpiConfig::default()
            .with_frequency(Rate::from_khz(sd_card::SPI_INIT_FREQUENCY_KHZ))
            .with_mode(SpiMode::_0),
    )
    .unwrap()
    .with_sck(sd_spi_clock_gpio)
    .with_mosi(sd_mosi_gpio)
    .with_miso(sd_miso_gpio);

    sd_spi_bus.write(&STARTUP_CLOCK_BYTES).unwrap();

    let sd_chip_select_output =
        Output::new(sd_chip_select_gpio, Level::High, OutputConfig::default());

    let sd_spi_device = embedded_hal_bus::spi::ExclusiveDevice::new(
        sd_spi_bus,
        sd_chip_select_output,
        Delay::new(),
    )
    .unwrap();
    let sd_card = SdCard::new(sd_spi_device, Delay::new());

    let size_mb = sd_card
        .num_bytes()
        .map(|bytes| (bytes / (1024 * 1024)) as u32)
        .unwrap_or(0);

    if size_mb > 0 {
        info!(
            "SD card detected (CS=GPIO{}, MOSI=GPIO{}, SCK=GPIO{}, MISO=GPIO{}, size={} MiB)",
            sd_card::CS_GPIO,
            sd_card::MOSI_GPIO,
            sd_card::SCK_GPIO,
            sd_card::MISO_GPIO,
            size_mb
        );
    }

    SD_STORAGE.0.lock(|cell| {
        cell.borrow_mut()
            .replace(VolumeManager::new(sd_card, SntpTimeSource));
    });

    size_mb
}

// ─── Internal helpers ──────────────────────────────────────────────────────────

/// Run an operation with the SD card volume manager.
fn with_sd<T>(
    operation: impl FnOnce(&SdVm) -> Result<T, SdError>,
) -> Result<T, SdError> {
    SD_STORAGE.0.lock(|cell| {
        let borrow = cell.borrow();
        let volume_manager = borrow.as_ref().ok_or(SdError::NotInitialized)?;
        operation(volume_manager)
    })
}

/// Open volume 0, open root dir, navigate to `dir_path` (if non-empty),
/// then hand the positioned directory handle to `operation`.
fn with_dir_at<T>(
    dir_path: &str,
    operation: impl FnOnce(&SdDir<'_>) -> Result<T, SdError>,
) -> Result<T, SdError> {
    with_sd(|volume_manager| {
        let volume = volume_manager
            .open_volume(VolumeIdx(0))
            .map_err(|_| SdError::VolumeFailed)?;
        let mut directory = volume
            .open_root_dir()
            .map_err(|_| SdError::RootDirFailed)?;
        if !dir_path.is_empty() {
            navigate_to(&mut directory, dir_path)?;
        }
        operation(&directory)
    })
}

/// Navigate a directory handle to a path by walking each segment.
fn navigate_to(directory: &mut SdDir<'_>, path: &str) -> Result<(), SdError> {
    for segment in path.split('/').filter(|s| !s.is_empty() && *s != ".") {
        directory
            .change_dir(segment)
            .map_err(|_| SdError::NavigationFailed)?;
    }
    Ok(())
}

// ─── Public API ────────────────────────────────────────────────────────────────

pub fn ensure_data_csv_exists() -> Result<(), SdError> {
    with_dir_at("", |root| {
        if root.directory_entry_exists(sd_card::DATA_CSV_FILE_NAME) {
            return Ok(());
        }
        let file = root
            .open_file_in_dir(sd_card::DATA_CSV_FILE_NAME, Mode::ReadWriteCreateOrTruncate)
            .map_err(|_| SdError::CreateFailed)?;
        file.write(sd_card::DATA_CSV_HEADER.as_bytes())
            .map_err(|_| SdError::WriteFailed)?;
        file.write(b"\n").map_err(|_| SdError::WriteFailed)?;
        file.flush().map_err(|_| SdError::FlushFailed)?;
        info!("created {} with CSV header", sd_card::DATA_CSV_FILE_NAME);
        Ok(())
    })
}

pub fn append_data_csv_line(line: &str) -> Result<(), SdError> {
    with_dir_at("", |root| {
        let file = root
            .open_file_in_dir(sd_card::DATA_CSV_FILE_NAME, Mode::ReadWriteCreateOrAppend)
            .map_err(|_| SdError::FileNotFound)?;
        file.write(line.as_bytes())
            .map_err(|_| SdError::WriteFailed)?;
        file.flush().map_err(|_| SdError::FlushFailed)?;
        Ok(())
    })
}

pub fn directory_exists(path: &str) -> bool {
    with_dir_at(path, |_directory| Ok(())).is_ok()
}

pub fn list_filesystem_entries()
    -> Result<HeaplessVec<FilesystemEntryPayload, MAX_FS_ENTRIES>, SdError>
{
    list_directory_at("")
}

pub fn list_directory_at(
    path: &str,
) -> Result<HeaplessVec<FilesystemEntryPayload, MAX_FS_ENTRIES>, SdError> {
    with_dir_at(path, |directory| {
        let mut entries = HeaplessVec::<FilesystemEntryPayload, 64>::new();
        directory
            .iterate_dir(|entry| {
                let mut name = HeaplessString::<32>::new();
                if write!(name, "{}", entry.name).is_err() {
                    return core::ops::ControlFlow::Continue(());
                }
                if name == "." || name == ".." {
                    return core::ops::ControlFlow::Continue(());
                }
                let is_directory = entry.attributes.is_directory();
                let size = if is_directory { 0 } else { entry.size };
                let _ = entries.push(FilesystemEntryPayload {
                    name,
                    size,
                    last_write_unix: 0,
                    is_directory,
                });
                core::ops::ControlFlow::Continue(())
            })
            .map_err(|_| SdError::ReadFailed)?;
        Ok(entries)
    })
}

pub fn is_supported_flat_file_name(file_name: &str) -> bool {
    !file_name.is_empty()
        && !file_name.contains('/')
        && !file_name.contains('\\')
        && !file_name.contains("..")
}

pub fn read_file_at<const BUF: usize>(
    dir_path: &str,
    file_name: &str,
) -> Result<HeaplessVec<u8, BUF>, SdError> {
    with_dir_at(dir_path, |directory| {
        let file = directory
            .open_file_in_dir(file_name, Mode::ReadOnly)
            .map_err(|_| SdError::FileNotFound)?;
        let mut contents = HeaplessVec::<u8, BUF>::new();
        let mut read_buffer = [0u8; 256];
        while !file.is_eof() {
            let bytes_read = file
                .read(&mut read_buffer)
                .map_err(|_| SdError::ReadFailed)?;
            if bytes_read == 0 {
                break;
            }
            for &byte in &read_buffer[..bytes_read] {
                let _ = contents.push(byte);
            }
        }
        Ok(contents)
    })
}

pub fn read_file_contents<const BUF: usize>(
    file_name: &str,
) -> Result<HeaplessVec<u8, BUF>, SdError> {
    read_file_at::<BUF>("", file_name)
}

pub fn delete_at(dir_path: &str, name: &str) -> Result<(), SdError> {
    with_dir_at(dir_path, |directory| {
        directory
            .delete_entry_in_dir(name)
            .map_err(|_| SdError::DeleteFailed)
    })
}

pub fn mkdir_at(dir_path: &str, name: &str) -> Result<(), SdError> {
    with_dir_at(dir_path, |directory| {
        directory
            .make_dir_in_dir(name)
            .map_err(|_| SdError::DirectoryFailed)?;
        Ok(())
    })
}

pub fn touch_at(dir_path: &str, name: &str) -> Result<(), SdError> {
    with_dir_at(dir_path, |directory| {
        let _file = directory
            .open_file_in_dir(name, Mode::ReadWriteCreateOrTruncate)
            .map_err(|_| SdError::CreateFailed)?;
        Ok(())
    })
}

pub fn file_size(file_name: &str) -> Result<u32, SdError> {
    file_size_at("", file_name)
}

pub fn file_size_at(dir_path: &str, file_name: &str) -> Result<u32, SdError> {
    with_dir_at(dir_path, |directory| {
        let entry = directory
            .find_directory_entry(file_name)
            .map_err(|_| SdError::FileNotFound)?;
        Ok(entry.size)
    })
}

pub fn read_file_chunk_at(
    dir_path: &str,
    file_name: &str,
    offset: u32,
    buf: &mut [u8],
) -> Result<usize, SdError> {
    with_dir_at(dir_path, |directory| {
        let file = directory
            .open_file_in_dir(file_name, Mode::ReadOnly)
            .map_err(|_| SdError::FileNotFound)?;
        file.seek_from_start(offset)
            .map_err(|_| SdError::SeekFailed)?;
        file.read(buf).map_err(|_| SdError::ReadFailed)
    })
}

pub fn read_file_chunk(file_name: &str, offset: u32, buf: &mut [u8]) -> Result<usize, SdError> {
    read_file_chunk_at("", file_name, offset, buf)
}

pub fn write_file_at(dir_path: &str, file_name: &str, data: &[u8]) -> Result<(), SdError> {
    with_dir_at(dir_path, |directory| {
        let file = directory
            .open_file_in_dir(file_name, Mode::ReadWriteCreateOrTruncate)
            .map_err(|_| SdError::FileNotFound)?;
        file.write(data).map_err(|_| SdError::WriteFailed)?;
        file.flush().map_err(|_| SdError::FlushFailed)?;
        Ok(())
    })
}

pub fn write_file_chunk(file_name: &str, offset: u32, data: &[u8]) -> Result<(), SdError> {
    let mode = if offset == 0 {
        Mode::ReadWriteCreateOrTruncate
    } else {
        Mode::ReadWriteCreateOrAppend
    };
    with_dir_at("", |directory| {
        let file = directory
            .open_file_in_dir(file_name, mode)
            .map_err(|_| SdError::FileNotFound)?;
        if offset > 0 {
            file.seek_from_start(offset)
                .map_err(|_| SdError::SeekFailed)?;
        }
        file.write(data).map_err(|_| SdError::WriteFailed)?;
        file.flush().map_err(|_| SdError::FlushFailed)?;
        Ok(())
    })
}

pub fn write_file_all(file_name: &str, chunks: &[&[u8]]) -> Result<u32, SdError> {
    with_dir_at("", |directory| {
        let file = directory
            .open_file_in_dir(file_name, Mode::ReadWriteCreateOrTruncate)
            .map_err(|_| SdError::FileNotFound)?;
        let mut total = 0u32;
        for chunk in chunks {
            file.write(chunk).map_err(|_| SdError::WriteFailed)?;
            total += chunk.len() as u32;
        }
        file.flush().map_err(|_| SdError::FlushFailed)?;
        Ok(total)
    })
}

pub fn overwrite_file_contents(file_name: &str, contents: &[u8]) -> Result<(), SdError> {
    write_file_all(file_name, &[contents]).map(|_| ())
}

pub fn create_directory(name: &str) -> Result<(), SdError> {
    with_dir_at("", |directory| {
        directory
            .make_dir_in_dir(name)
            .map_err(|_| SdError::DirectoryFailed)?;
        Ok(())
    })
}

pub fn delete_file(name: &str) -> Result<(), SdError> {
    with_dir_at("", |directory| {
        directory
            .delete_entry_in_dir(name)
            .map_err(|_| SdError::DeleteFailed)
    })
}

pub fn copy_file(source: &str, destination: &str) -> Result<u32, SdError> {
    with_dir_at("", |directory| {
        let source_file = directory
            .open_file_in_dir(source, Mode::ReadOnly)
            .map_err(|_| SdError::FileNotFound)?;
        let destination_file = directory
            .open_file_in_dir(destination, Mode::ReadWriteCreateOrTruncate)
            .map_err(|_| SdError::CreateFailed)?;
        let mut buffer = [0u8; 4096];
        let mut total = 0u32;
        while !source_file.is_eof() {
            let bytes_read = source_file
                .read(&mut buffer)
                .map_err(|_| SdError::ReadFailed)?;
            if bytes_read == 0 {
                break;
            }
            destination_file
                .write(&buffer[..bytes_read])
                .map_err(|_| SdError::WriteFailed)?;
            total += bytes_read as u32;
        }
        destination_file
            .flush()
            .map_err(|_| SdError::FlushFailed)?;
        Ok(total)
    })
}
