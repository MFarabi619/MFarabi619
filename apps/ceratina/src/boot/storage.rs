use crate::{filesystems::sd, power, services};

pub fn initialize_sd_and_filesystem(
    spi: esp_hal::peripherals::SPI2<'static>,
    cs: esp_hal::peripherals::GPIO10<'static>,
    mosi: esp_hal::peripherals::GPIO11<'static>,
    sck: esp_hal::peripherals::GPIO12<'static>,
    miso: esp_hal::peripherals::GPIO13<'static>,
) {
    sd::initialize(spi, cs, mosi, sck, miso);
    services::data_logger::ensure_initialized();
    power::sleep::initialize();
    services::system_files::initialize_layout();
}
