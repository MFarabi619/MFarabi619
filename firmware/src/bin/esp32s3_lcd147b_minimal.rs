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
        Mode,
        master::{Config as SpiConfig, Spi},
    },
    time::Rate,
};
use mipidsi::{
    Builder,
    interface::SpiInterface,
    models::ST7789,
    options::{ColorOrder, Orientation, Rotation},
};
use mousefood::{
    embedded_graphics::{
        draw_target::DrawTarget,
        pixelcolor::{Rgb565, RgbColor},
    },
    prelude::*,
};
use panic_rtt_target as _;
use ratatui::{
    Frame, Terminal,
    style::*,
    widgets::{Block, Paragraph, Wrap},
};

const LCD_WIDTH: u16 = 172;
const LCD_HEIGHT: u16 = 320;
const LCD_X_OFFSET: u16 = 34;

esp_bootloader_esp_idf::esp_app_desc!();

#[main]
fn main() -> ! {
    rtt_target::rtt_init_defmt!();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(size: 128 * 1024);

    let delay = Delay::new();

    let _backlight = Output::new(peripherals.GPIO46, Level::High, OutputConfig::default());
    let rst = Output::new(peripherals.GPIO39, Level::High, OutputConfig::default());

    let spi = Spi::new(
        peripherals.SPI2,
        SpiConfig::default()
            .with_frequency(Rate::from_mhz(40))
            .with_mode(Mode::_0),
    )
    .unwrap()
    .with_sck(peripherals.GPIO40)
    .with_mosi(peripherals.GPIO45);

    let cs = Output::new(peripherals.GPIO42, Level::High, OutputConfig::default());
    let spi_device = embedded_hal_bus::spi::ExclusiveDevice::new(spi, cs, delay).unwrap();

    let dc = Output::new(peripherals.GPIO41, Level::High, OutputConfig::default());
    let buffer = Box::leak(Box::new([0_u8; 4096]));
    let spi_interface = SpiInterface::new(spi_device, dc, buffer);

    let mut delay = Delay::new();
    let mut display = Builder::new(ST7789, spi_interface)
        .display_size(LCD_WIDTH, LCD_HEIGHT)
        .display_offset(LCD_X_OFFSET, 0)
        .orientation(Orientation::default().rotate(Rotation::Deg270))
        .color_order(ColorOrder::Bgr)
        .reset_pin(rst)
        .init(&mut delay)
        .expect("Failed to init ST7789 display");

    let _ = display.clear(Rgb565::BLACK);

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
