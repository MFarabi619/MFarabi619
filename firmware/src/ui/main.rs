#![no_std]
#![no_main]
#![deny(
    clippy::mem_forget,
    reason = "mem::forget is generally not safe to do with esp_hal types, especially those \
    holding buffers for the duration of a data transfer."
)]
#![deny(clippy::large_stack_frames)]

extern crate alloc;

mod button;
mod chart;
mod gauge;
mod helpers;
mod lorem;
mod ratatui_logo;
mod tabs;
mod voltage;

use alloc::boxed::Box;
use button::Button;
use chart::ChartApp;
use esp_hal::{
    analog::adc::{Adc, AdcConfig, Attenuation},
    clock::CpuClock,
    delay::Delay,
    gpio::{Input, InputConfig, Level, Output, OutputConfig, Pull},
    main,
    spi::{
        Mode,
        master::{Config as SpiConfig, Spi},
    },
    time::{Duration, Rate},
};
use gauge::GaugeApp;
use mipidsi::{
    Builder,
    interface::SpiInterface,
    models::ILI9341Rgb565,
    options::{ColorOrder, Orientation, Rotation},
};
use mousefood::prelude::*;
use ratatui::Terminal;
use ratatui_logo::RatatuiLogoApp;
use tabs::TabsApp;
use voltage::VoltageApp;

#[panic_handler]
fn panic(panic_info: &core::panic::PanicInfo) -> ! {
    loop {
        log::error!("{panic_info:?}");
    }
}

esp_bootloader_esp_idf::esp_app_desc!();

#[allow(
    clippy::large_stack_frames,
    reason = "it's not unusual to allocate larger buffers etc. in main"
)]
#[main]
fn main() -> ! {
    esp_println::logger::init_logger_from_env();
    log::info!("Starting Mousefood example app");

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(size: 128 * 1024);

    let _backlight = Output::new(peripherals.GPIO21, Level::High, OutputConfig::default());

    let spi = Spi::new(
        peripherals.SPI2,
        SpiConfig::default()
            .with_frequency(Rate::from_mhz(20))
            .with_mode(Mode::_0),
    )
    .unwrap()
    .with_sck(peripherals.GPIO14)
    .with_mosi(peripherals.GPIO13)
    .with_miso(peripherals.GPIO12);

    let cs = Output::new(peripherals.GPIO15, Level::High, OutputConfig::default());
    let spi_device = embedded_hal_bus::spi::ExclusiveDevice::new(spi, cs, Delay::new()).unwrap();

    let dc = Output::new(peripherals.GPIO2, Level::High, OutputConfig::default());
    let buffer = Box::leak(Box::new([0_u8; 4096]));
    let spi_interface = SpiInterface::new(spi_device, dc, buffer);

    let mut delay = Delay::new();
    let mut display = Builder::new(ILI9341Rgb565, spi_interface)
        .display_size(240, 320)
        .orientation(Orientation::new().rotate(Rotation::Deg90).flip_horizontal())
        .color_order(ColorOrder::Bgr)
        .init(&mut delay)
        .expect("Failed to init display");

    let button_pin = Input::new(
        peripherals.GPIO0,
        InputConfig::default().with_pull(Pull::Up),
    );
    let mut button = Button::new(button_pin, Duration::from_millis(150));

    let mut adc_config = AdcConfig::new();
    let mut battery_adc = adc_config.enable_pin(peripherals.GPIO34, Attenuation::_11dB);
    let mut adc = Adc::new(peripherals.ADC1, adc_config);

    let backend = EmbeddedBackend::new(&mut display, Default::default());
    let mut terminal = Terminal::new(backend).unwrap();

    loop {
        RatatuiLogoApp::new().run(&mut terminal, &mut button, &delay);
        delay.delay_millis(200);

        TabsApp::new().run(&mut terminal, &mut button, &delay);
        delay.delay_millis(200);

        ChartApp::new().run(&mut terminal, &mut button, &delay);
        delay.delay_millis(200);

        GaugeApp::new().run(&mut terminal, &mut button, &delay);
        delay.delay_millis(200);

        let mut read_voltage = || adc.read_oneshot(&mut battery_adc).ok();
        VoltageApp::new().run(&mut terminal, &mut button, &delay, &mut read_voltage);
        delay.delay_millis(200);
    }
}
