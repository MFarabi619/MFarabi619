use std::{thread::sleep, time::Duration};

use super::{
    gpio::{Connection, Error},
    spi::Spi,
};

pub const LED_COUNT: usize = 4;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Color {
    pub red: u8,
    pub green: u8,
    pub blue: u8,
}

pub const OFF: Color = Color {
    red: 0,
    green: 0,
    blue: 0,
};
pub const RED: Color = Color {
    red: 255,
    green: 0,
    blue: 0,
};
pub const GREEN: Color = Color {
    red: 0,
    green: 255,
    blue: 0,
};
pub const BLUE: Color = Color {
    red: 0,
    green: 0,
    blue: 255,
};
pub const WHITE: Color = Color {
    red: 255,
    green: 255,
    blue: 255,
};

pub type Frame = [Color; LED_COUNT];
pub const DARK: Frame = [OFF; LED_COUNT];

const SPI_BUS: u32 = 0;
const SPI_CHANNEL: u32 = 0;
const SPI_MODE: u32 = 0;
const SPI_CLOCK_HZ: u32 = 6_400_000;
const BITS_PER_CHANNEL: usize = 8;
const WS2812_BIT_ZERO: u8 = 0x80;
const WS2812_BIT_ONE: u8 = 0xF8;
const WHEEL_SPAN: u8 = 85;
const WHEEL_SPAN_LAST: u8 = 84;
const WHEEL_SPAN_TWICE_LAST: u8 = 169;
const CHASE_STEPS: u16 = 64;
const CHASE_STRIDE: u16 = 4;
const CHANNEL_MAX: u8 = 255;
const WHEEL_RAMP_SLOPE: u8 = 3;
const WHEEL_SIZE: u32 = 256;
const WHEEL_INDEX_MASK: u32 = 0xFF;
const CHANNELS_PER_LED: usize = 3;

pub fn color_wheel(position: u8) -> Color {
    match position {
        0..=WHEEL_SPAN_LAST => Color {
            red: position * WHEEL_RAMP_SLOPE,
            green: CHANNEL_MAX - position * WHEEL_RAMP_SLOPE,
            blue: 0,
        },
        WHEEL_SPAN..=WHEEL_SPAN_TWICE_LAST => {
            let position = position - WHEEL_SPAN;
            Color {
                red: CHANNEL_MAX - position * WHEEL_RAMP_SLOPE,
                green: 0,
                blue: position * WHEEL_RAMP_SLOPE,
            }
        }
        _ => {
            let position = position - 2 * WHEEL_SPAN;
            Color {
                red: 0,
                green: position * WHEEL_RAMP_SLOPE,
                blue: CHANNEL_MAX - position * WHEEL_RAMP_SLOPE,
            }
        }
    }
}

fn rainbow_frame(shift: u8) -> Frame {
    let mut frame = DARK;
    for (index, color) in frame.iter_mut().enumerate() {
        *color = color_wheel((index as u8).wrapping_add(shift));
    }
    frame
}

fn rainbow_cycle_frame(shift: u8) -> Frame {
    let mut frame = DARK;
    for (index, color) in frame.iter_mut().enumerate() {
        let position = (index * WHEEL_SIZE as usize / LED_COUNT) as u8;
        *color = color_wheel(position.wrapping_add(shift));
    }
    frame
}

fn encode(frame: &Frame) -> Vec<u8> {
    let mut spi_bytes = Vec::with_capacity(LED_COUNT * CHANNELS_PER_LED * BITS_PER_CHANNEL);
    for color in frame {
        for channel in [color.green, color.red, color.blue] {
            for bit_index in (0..BITS_PER_CHANNEL).rev() {
                let bit_is_set = ((channel >> bit_index) & 1) == 1;
                spi_bytes.push(if bit_is_set {
                    WS2812_BIT_ONE
                } else {
                    WS2812_BIT_ZERO
                });
            }
        }
    }
    spi_bytes
}

pub struct LedStrip<'a> {
    spi: Spi<'a>,
    frame: Frame,
}

impl<'a> LedStrip<'a> {
    pub fn open(connection: &'a Connection) -> Result<Self, Error> {
        let spi = Spi::open(connection, SPI_BUS, SPI_CHANNEL, SPI_CLOCK_HZ, SPI_MODE)?;
        let mut strip = Self { spi, frame: DARK };
        strip.show(DARK)?;
        Ok(strip)
    }

    pub fn show(&mut self, frame: Frame) -> Result<(), Error> {
        self.spi.write(&encode(&frame))?;
        self.frame = frame;
        Ok(())
    }

    pub fn fill(&mut self, color: Color) -> Result<(), Error> {
        self.show([color; LED_COUNT])
    }

    pub fn set(&mut self, index: usize, color: Color) -> Result<(), Error> {
        let mut frame = self.frame;
        frame[index] = color;
        self.show(frame)
    }

    pub fn color_wipe(&mut self, color: Color, wait: Duration) -> Result<(), Error> {
        for lit in 1..=LED_COUNT {
            let mut frame = self.frame;
            frame[..lit].fill(color);
            self.show(frame)?;
            sleep(wait);
        }
        Ok(())
    }

    pub fn rainbow(&mut self, wait: Duration, cycles: u16) -> Result<(), Error> {
        for step in 0..(WHEEL_SIZE * cycles as u32) {
            self.show(rainbow_frame((step & WHEEL_INDEX_MASK) as u8))?;
            sleep(wait);
        }
        Ok(())
    }

    pub fn rainbow_cycle(&mut self, wait: Duration, cycles: u16) -> Result<(), Error> {
        for step in 0..(WHEEL_SIZE * cycles as u32) {
            self.show(rainbow_cycle_frame((step & WHEEL_INDEX_MASK) as u8))?;
            sleep(wait);
        }
        Ok(())
    }

    pub fn theater_chase_rainbow(&mut self, wait: Duration) -> Result<(), Error> {
        let mut frame = DARK;
        for step in 0..CHASE_STEPS {
            for index in 0..LED_COUNT {
                frame[index] = color_wheel(((index as u16 + step * CHASE_STRIDE) % 255) as u8);
                self.show(frame)?;
                sleep(wait);
                frame[index] = OFF;
            }
        }
        Ok(())
    }
}

impl Drop for LedStrip<'_> {
    fn drop(&mut self) {
        let _ = self.show(DARK);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wheel_hits_the_primary_corners() {
        assert_eq!(
            color_wheel(0),
            Color {
                red: 0,
                green: 255,
                blue: 0,
            }
        );
        assert_eq!(
            color_wheel(85),
            Color {
                red: 255,
                green: 0,
                blue: 0,
            }
        );
        assert_eq!(
            color_wheel(170),
            Color {
                red: 0,
                green: 0,
                blue: 255,
            }
        );
    }

    #[test]
    fn encode_is_per_led_grb_first() {
        let green = Color {
            red: 0,
            green: 255,
            blue: 0,
        };
        let frame = [green, OFF, OFF, OFF];
        let bytes = encode(&frame);
        assert_eq!(bytes.len(), LED_COUNT * CHANNELS_PER_LED * BITS_PER_CHANNEL);
        assert!(bytes[0..BITS_PER_CHANNEL]
            .iter()
            .all(|&byte| byte == WS2812_BIT_ONE));
        assert!(bytes[BITS_PER_CHANNEL..]
            .iter()
            .all(|&byte| byte == WS2812_BIT_ZERO));
    }

    #[test]
    fn rainbow_frame_shifts_along_the_color_wheel() {
        let frame = rainbow_frame(0);
        assert_eq!(frame[0], color_wheel(0));
        assert_eq!(frame[1], color_wheel(1));
    }
}
