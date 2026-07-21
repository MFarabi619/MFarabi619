use std::convert::Infallible;

use embedded_graphics::{pixelcolor::Rgb565, prelude::*};
use mousefood::{EmbeddedBackend, EmbeddedBackendConfig};
use ratatui::{
    widgets::{Block, Paragraph},
    Frame, Terminal,
};
use robot_drivers::{
    gpio::{Connection, Error},
    i2c::I2c,
    ssd1306::{Ssd1306, BUFFER_LEN, HEIGHT, WIDTH},
};

const HOST: &str = "beagleyai";
const RGPIOD_PORT: u16 = 8889;
const I2C_BUS: u32 = 1;
const OLED_ADDRESS: u32 = 0x3c;

struct Ssd1306Canvas<'a> {
    display: Ssd1306<'a>,
    frame: [u8; BUFFER_LEN],
}

impl<'a> Ssd1306Canvas<'a> {
    fn new(display: Ssd1306<'a>) -> Self {
        Self {
            display,
            frame: [0; BUFFER_LEN],
        }
    }

    fn flush(&self) -> Result<(), Error> {
        self.display.draw(&self.frame)
    }
}

impl OriginDimensions for Ssd1306Canvas<'_> {
    fn size(&self) -> Size {
        Size::new(WIDTH as u32, HEIGHT as u32)
    }
}

impl DrawTarget for Ssd1306Canvas<'_> {
    type Color = Rgb565;
    type Error = Infallible;

    fn draw_iter<I>(&mut self, pixels: I) -> Result<(), Self::Error>
    where
        I: IntoIterator<Item = Pixel<Self::Color>>,
    {
        for Pixel(coordinate, color) in pixels {
            if coordinate.x < 0
                || coordinate.y < 0
                || coordinate.x >= WIDTH as i32
                || coordinate.y >= HEIGHT as i32
            {
                continue;
            }
            let index = coordinate.x as usize + (coordinate.y as usize / 8) * WIDTH;
            let mask = 1u8 << (coordinate.y as usize % 8);
            if color == Rgb565::BLACK {
                self.frame[index] &= !mask;
            } else {
                self.frame[index] |= mask;
            }
        }
        Ok(())
    }
}

fn draw(frame: &mut Frame) {
    let block = Block::bordered().title("beagleyai");
    let body = Paragraph::new("online").block(block);
    frame.render_widget(body, frame.area());
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let connection: &'static Connection =
        Box::leak(Box::new(Connection::connect(HOST, RGPIOD_PORT)?));
    let i2c = I2c::open(connection, I2C_BUS, OLED_ADDRESS)?;
    let mut canvas = Ssd1306Canvas::new(Ssd1306::new(i2c)?);

    let backend = EmbeddedBackend::new(
        &mut canvas,
        EmbeddedBackendConfig {
            flush_callback: Box::new(|canvas| canvas.flush().expect("flush oled over rgpio")),
            ..Default::default()
        },
    );
    let mut terminal = Terminal::new(backend)?;
    terminal.draw(draw)?;
    Ok(())
}
