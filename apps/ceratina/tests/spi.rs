//! SPI SD card integration test for the ESP32-S3 board.
//!
//! This uses the generic ESP32-S3 Arduino SPI pin mapping that matched the
//! previous working Arduino firmware:
//! - CS   => GPIO10
//! - MOSI => GPIO11
//! - SCK  => GPIO12
//! - MISO => GPIO13

#![no_std]
#![no_main]

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

const SD_CHIP_SELECT_PIN: u32 = 10;
const SD_MOSI_PIN: u32 = 11;
const SD_SPI_CLOCK_PIN: u32 = 12;
const SD_MISO_PIN: u32 = 13;
const SD_SPI_INIT_FREQUENCY_KHZ: u32 = 400;
const SPI_STARTUP_CLOCK_BYTES: [u8; 10] = [0xFF; 10];
const TEST_FILE_NAME: &str = "RUSTTEST.TXT";
const TEST_FILE_CONTENTS: &[u8] = b"hello from rust spi sd test\n";

struct Context {
    spi2: SPI2<'static>,
    sd_chip_select_pin: GPIO10<'static>,
    sd_mosi_pin: GPIO11<'static>,
    sd_spi_clock_pin: GPIO12<'static>,
    sd_miso_pin: GPIO13<'static>,
}

struct FixedTimeSource;

impl TimeSource for FixedTimeSource {
    fn get_timestamp(&self) -> Timestamp {
        Timestamp::from_calendar(2026, 4, 2, 12, 0, 0).unwrap()
    }
}

fn create_spi_bus(context: Context) -> (Spi<'static, esp_hal::Blocking>, Output<'static>) {
    let spi = Spi::new(
        context.spi2,
        SpiConfig::default()
            .with_frequency(Rate::from_khz(SD_SPI_INIT_FREQUENCY_KHZ))
            .with_mode(SpiMode::_0),
    )
    .unwrap()
    .with_sck(context.sd_spi_clock_pin)
    .with_mosi(context.sd_mosi_pin)
    .with_miso(context.sd_miso_pin);

    let chip_select = Output::new(
        context.sd_chip_select_pin,
        Level::High,
        OutputConfig::default(),
    );

    (spi, chip_select)
}

fn clock_idle_spi_cycles(spi: &mut Spi<'static, esp_hal::Blocking>) {
    defmt::unwrap!(spi.write(&SPI_STARTUP_CLOCK_BYTES), "SPI startup clock write failed");
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
            "SPI SD test initialized (CS=GPIO{}, MOSI=GPIO{}, SCK=GPIO{}, MISO=GPIO{})",
            SD_CHIP_SELECT_PIN,
            SD_MOSI_PIN,
            SD_SPI_CLOCK_PIN,
            SD_MISO_PIN
        );

        Context {
            spi2: peripherals.SPI2,
            sd_chip_select_pin: peripherals.GPIO10,
            sd_mosi_pin: peripherals.GPIO11,
            sd_spi_clock_pin: peripherals.GPIO12,
            sd_miso_pin: peripherals.GPIO13,
        }
    }

    #[test]
    async fn sd_card_over_spi_roundtrip(context: Context) {
        let (mut spi_bus, chip_select) = create_spi_bus(context);

        info!("sending initial idle clocks for SPI SD card startup");
        clock_idle_spi_cycles(&mut spi_bus);

        let spi_device =
            embedded_hal_bus::spi::ExclusiveDevice::new(spi_bus, chip_select, Delay::new())
                .unwrap();

        let sd_card = SdCard::new(spi_device, Delay::new());

        let card_size_bytes = sd_card.num_bytes().unwrap();
        let card_size_megabytes = card_size_bytes / (1024 * 1024);

        info!("SPI SD card detected: {=u64} MiB", card_size_megabytes);
        info!("SPI SD card type: {=?}", sd_card.get_card_type());
        defmt::assert!(card_size_megabytes > 0, "card reports zero size");

        let volume_manager = VolumeManager::new(sd_card, FixedTimeSource);
        let volume0 = volume_manager.open_volume(VolumeIdx(0)).unwrap();
        let root_directory = volume0.open_root_dir().unwrap();

        let mut root_entry_count = 0usize;
        root_directory
            .iterate_dir(|directory_entry| {
                root_entry_count += 1;
                if root_entry_count <= 8 {
                    info!(
                        "root entry {=usize}: {=?} ({=u32} bytes)",
                        root_entry_count,
                        directory_entry.name,
                        directory_entry.size
                    );
                }
                core::ops::ControlFlow::Continue(())
            })
            .unwrap();

        info!("root directory entries observed: {=usize}", root_entry_count);
        defmt::assert!(root_entry_count > 0, "root directory is empty");

        // Write test file
        let test_file = root_directory
            .open_file_in_dir(TEST_FILE_NAME, Mode::ReadWriteCreateOrTruncate)
            .unwrap();

        test_file.write(TEST_FILE_CONTENTS).unwrap();
        test_file.flush().unwrap();
        info!("wrote {=usize} bytes to {=str}", TEST_FILE_CONTENTS.len(), TEST_FILE_NAME);

        // Read back and verify
        test_file.seek_from_start(0).unwrap();

        let mut read_buffer = [0u8; TEST_FILE_CONTENTS.len()];
        let read_count = test_file.read(&mut read_buffer).unwrap();
        defmt::assert_eq!(read_count, TEST_FILE_CONTENTS.len());
        defmt::assert_eq!(read_buffer.as_slice(), TEST_FILE_CONTENTS);

        info!("SPI SD card roundtrip read verified");

        // Clean up
        test_file.close().unwrap();
        root_directory.delete_entry_in_dir(TEST_FILE_NAME).unwrap();
        info!("deleted {=str}", TEST_FILE_NAME);

        root_directory.close().unwrap();
        volume0.close().unwrap();
    }
}
