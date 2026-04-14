#![no_std]
#![no_main]

use core::ops::ControlFlow;
use defmt::info;
use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use embedded_hal_bus::spi::ExclusiveDevice;
use embedded_sdmmc::{Mode, SdCard, TimeSource, Timestamp, VolumeIdx, VolumeManager};
use esp_hal::{
    clock::CpuClock,
    delay::Delay,
    gpio::{Level, Output, OutputConfig},
    interrupt::software::SoftwareInterruptControl,
    spi::master::{Config as SpiConfig, Spi},
    time::Rate,
    timer::timg::TimerGroup,
};
use panic_rtt_target as _;

const SD_SPI_FREQUENCY_KHZ: u32 = 400;

esp_bootloader_esp_idf::esp_app_desc!();

#[derive(Default)]
pub struct DummyTimesource;

impl TimeSource for DummyTimesource {
    fn get_timestamp(&self) -> Timestamp {
        Timestamp {
            year_since_1970: 0,
            zero_indexed_month: 0,
            zero_indexed_day: 0,
            hours: 0,
            minutes: 0,
            seconds: 0,
        }
    }
}

#[esp_rtos::main]
async fn main(_spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 64 * 1024);
    esp_alloc::heap_allocator!(size: 64 * 1024);

    let timer_group0 = TimerGroup::new(peripherals.TIMG0);
    let sw_ints = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
    esp_rtos::start(timer_group0.timer0, sw_ints.software_interrupt0);

    info!("SD card read example initialized");

    let spi_bus = Spi::new(
        peripherals.SPI2,
        SpiConfig::default()
            .with_frequency(Rate::from_khz(SD_SPI_FREQUENCY_KHZ))
            .with_mode(esp_hal::spi::Mode::_0),
    )
    .unwrap()
    .with_sck(peripherals.GPIO12)
    .with_mosi(peripherals.GPIO11)
    .with_miso(peripherals.GPIO13)
    .into_async();

    let chip_select = Output::new(peripherals.GPIO10, Level::High, OutputConfig::default());

    let spi_device = ExclusiveDevice::new(spi_bus, chip_select, Delay::new()).unwrap();
    let sd_card = SdCard::new(spi_device, Delay::new());

    let card_size_bytes = sd_card.num_bytes().unwrap();
    let card_size_megabytes = card_size_bytes / (1024 * 1024);
    info!("SD card detected: {} MiB", card_size_megabytes);

    let volume_manager = VolumeManager::new(sd_card, DummyTimesource::default());
    let volume0 = volume_manager.open_volume(VolumeIdx(0)).unwrap();
    let root_directory = volume0.open_root_dir().unwrap();

    info!("listing root directory:");
    root_directory
        .iterate_dir(|directory_entry| {
            info!(
                "  {:?} ({} bytes)",
                directory_entry.name, directory_entry.size
            );
            ControlFlow::Continue(())
        })
        .unwrap();

    let test_file_result = root_directory.open_file_in_dir("FERRIS.TXT", Mode::ReadOnly);

    match test_file_result {
        Ok(file) => {
            info!("reading FERRIS.TXT:");
            let mut buffer = [0u8; 64];

            while !file.is_eof() {
                if let Ok(bytes_read) = file.read(&mut buffer) {
                    for byte in &buffer[..bytes_read] {
                        info!("{}", *byte as char);
                    }
                }
            }
        }
        Err(_) => {
            info!("FERRIS.TXT not found, creating it");
            let new_file = root_directory
                .open_file_in_dir("FERRIS.TXT", Mode::ReadWriteCreateOrTruncate)
                .unwrap();

            let greeting = b"Hello, World!";
            new_file.write(greeting).unwrap();

            info!("created FERRIS.TXT with: Hello, World!");

            let read_file = root_directory
                .open_file_in_dir("FERRIS.TXT", Mode::ReadOnly)
                .unwrap();

            let mut buffer = [0u8; 64];
            while !read_file.is_eof() {
                if let Ok(bytes_read) = read_file.read(&mut buffer) {
                    for byte in &buffer[..bytes_read] {
                        info!("{}", *byte as char);
                    }
                }
            }
        }
    }

    loop {
        Timer::after(Duration::from_secs(30)).await;
    }
}
