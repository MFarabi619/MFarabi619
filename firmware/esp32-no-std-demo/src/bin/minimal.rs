#![no_std]
#![no_main]

extern crate alloc;

use alloc::boxed::Box;
use esp_hal::{
    clock::CpuClock,
    delay::Delay,
    gpio::{Level, Output, OutputConfig},
    main,
    spi::{
        master::{Config as SpiConfig, Spi},
        Mode,
    },
    time::Rate,
};
use mipidsi::{
    interface::SpiInterface,
    models::ILI9341Rgb565,
    options::{ColorOrder, Orientation, Rotation},
    Builder,
};
use mousefood::{
    embedded_graphics::{
        draw_target::DrawTarget,
        pixelcolor::{Rgb565, RgbColor},
    },
    prelude::*,
};
use ratatui::{
    style::*,
    widgets::{Block, Paragraph, Wrap},
    Frame, Terminal,
};

const RUN_COLOR_CYCLE_FIRST: bool = false;

#[panic_handler]
fn panic(panic_info: &core::panic::PanicInfo) -> ! {
    loop {
        log::error!("{panic_info:?}");
    }
}

esp_bootloader_esp_idf::esp_app_desc!();

#[main]
fn main() -> ! {
    esp_println::logger::init_logger_from_env();
    log::info!("Starting ESP32-32E simulator-style demo");

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(size: 128 * 1024);

    let _backlight = Output::new(peripherals.GPIO21, Level::High, OutputConfig::default());

    let lcd_spi = Spi::new(
        peripherals.SPI2,
        SpiConfig::default()
            .with_frequency(Rate::from_mhz(20))
            .with_mode(Mode::_0),
    )
    .unwrap()
    .with_sck(peripherals.GPIO14)
    .with_mosi(peripherals.GPIO13)
    .with_miso(peripherals.GPIO12);

    let lcd_cs = Output::new(peripherals.GPIO15, Level::High, OutputConfig::default());
    let lcd_device =
        embedded_hal_bus::spi::ExclusiveDevice::new(lcd_spi, lcd_cs, Delay::new()).unwrap();

    let lcd_dc = Output::new(peripherals.GPIO2, Level::High, OutputConfig::default());
    let buffer = Box::leak(Box::new([0_u8; 4096]));
    let lcd_interface = SpiInterface::new(lcd_device, lcd_dc, buffer);

    let mut delay = Delay::new();
    let mut display = Builder::new(ILI9341Rgb565, lcd_interface)
        .display_size(240, 320)
        .orientation(Orientation::new().rotate(Rotation::Deg90).flip_horizontal())
        .color_order(ColorOrder::Bgr)
        .init(&mut delay)
        .expect("Failed to init ILI9341 display");

    if RUN_COLOR_CYCLE_FIRST {
        loop {
            let _ = display.clear(Rgb565::RED);
            delay.delay_millis(1000);
            let _ = display.clear(Rgb565::GREEN);
            delay.delay_millis(1000);
            let _ = display.clear(Rgb565::BLUE);
            delay.delay_millis(1000);
            let _ = display.clear(Rgb565::WHITE);
            delay.delay_millis(1000);
        }
    }

    let backend = EmbeddedBackend::new(&mut display, Default::default());
    let mut terminal = Terminal::new(backend).unwrap();

    loop {
        let _ = terminal.draw(draw);
        delay.delay_millis(33);
    }
}

fn draw(frame: &mut Frame) {
    let text = "Ratatui on embedded devices!";
    let paragraph = Paragraph::new(text.dark_gray()).wrap(Wrap { trim: true });
    let bordered_block = Block::bordered()
        .border_style(Style::new().yellow())
        .title("Mousefood");
    frame.render_widget(paragraph.block(bordered_block), frame.area());
}
