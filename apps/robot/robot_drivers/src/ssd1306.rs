use super::{gpio::Error, i2c::I2c};

pub const WIDTH: usize = 128;
pub const HEIGHT: usize = 64;
const PAGES: usize = HEIGHT / 8;
pub const BUFFER_LEN: usize = WIDTH * PAGES;

const CONTROL_COMMAND: u8 = 0x00;
const CONTROL_DATA: u8 = 0x40;
const BLOCK_MAX: usize = 32;

const SET_COLUMN_RANGE: u8 = 0x21;
const SET_PAGE_RANGE: u8 = 0x22;

const INIT_SEQUENCE: [u8; 26] = [
    0xAE, 0x20, 0x00, 0xB0, 0xC8, 0x00, 0x10, 0x40, 0xA1, 0xA6, 0xA8, 0x3F, 0xA4, 0xD3, 0x00, 0xD5,
    0x80, 0xD9, 0xF1, 0xDA, 0x12, 0xDB, 0x40, 0x8D, 0x14, 0xAF,
];

pub struct Ssd1306<'a> {
    i2c: I2c<'a>,
}

impl<'a> Ssd1306<'a> {
    pub fn new(i2c: I2c<'a>) -> Result<Self, Error> {
        let display = Self { i2c };
        for &command in &INIT_SEQUENCE {
            display.command(command)?;
        }
        Ok(display)
    }

    fn command(&self, command: u8) -> Result<(), Error> {
        self.i2c.write_byte(CONTROL_COMMAND, command)
    }

    fn address_frame(&self) -> Result<(), Error> {
        self.command(SET_COLUMN_RANGE)?;
        self.command(0)?;
        self.command(WIDTH as u8 - 1)?;
        self.command(SET_PAGE_RANGE)?;
        self.command(0)?;
        self.command(PAGES as u8 - 1)
    }

    pub fn draw(&self, buffer: &[u8; BUFFER_LEN]) -> Result<(), Error> {
        self.address_frame()?;
        for chunk in buffer.chunks(BLOCK_MAX) {
            self.i2c.write_block(CONTROL_DATA, chunk)?;
        }
        Ok(())
    }

    pub fn fill(&self, pattern: u8) -> Result<(), Error> {
        self.draw(&[pattern; BUFFER_LEN])
    }

    pub fn clear(&self) -> Result<(), Error> {
        self.fill(0x00)
    }
}
