use std::{thread::sleep, time::Duration};

use super::{gpio::Error, i2c::I2c};

const MODE1: u8 = 0x00;
const PRESCALE: u8 = 0xFE;
const LED0_ON_L: u8 = 0x06;
const REGISTERS_PER_CHANNEL: u8 = 4;

const MODE1_SLEEP: u8 = 0x10;
const MODE1_AUTO_INCREMENT: u8 = 0x20;
const OSCILLATOR_SETTLE: Duration = Duration::from_millis(5);

const OSCILLATOR_HZ: f64 = 25_000_000.0;
const COUNTS_PER_PERIOD: f64 = 4096.0;
const SERVO_FREQUENCY_HZ: f64 = 50.0;
const PERIOD_USEC: f64 = 1_000_000.0 / SERVO_FREQUENCY_HZ;

const SERVO_MINIMUM_USEC: f64 = 500.0;
const SERVO_MAXIMUM_USEC: f64 = 2400.0;
const SERVO_RANGE_DEG: f64 = 180.0;
const PULSE_START_COUNT: u16 = 0;

pub struct Pca9685<'a> {
    i2c: I2c<'a>,
}

impl<'a> Pca9685<'a> {
    pub fn new(i2c: I2c<'a>) -> Result<Self, Error> {
        let controller = Self { i2c };
        controller.set_frequency(SERVO_FREQUENCY_HZ)?;
        Ok(controller)
    }

    fn set_frequency(&self, frequency_hz: f64) -> Result<(), Error> {
        let prescale = (OSCILLATOR_HZ / (COUNTS_PER_PERIOD * frequency_hz)).round() as u8 - 1;
        self.i2c.write_byte(MODE1, MODE1_SLEEP)?;
        self.i2c.write_byte(PRESCALE, prescale)?;
        self.i2c.write_byte(MODE1, MODE1_AUTO_INCREMENT)?;
        sleep(OSCILLATOR_SETTLE);
        Ok(())
    }

    pub fn set_channel(&self, channel: u8, on_count: u16, off_count: u16) -> Result<(), Error> {
        let register = LED0_ON_L + REGISTERS_PER_CHANNEL * channel;
        let [on_low, on_high] = on_count.to_le_bytes();
        let [off_low, off_high] = off_count.to_le_bytes();
        self.i2c
            .write_block(register, &[on_low, on_high, off_low, off_high])
    }

    pub fn set_servo_angle(&self, channel: u8, angle_deg: f64) -> Result<(), Error> {
        let angle = angle_deg.clamp(0.0, SERVO_RANGE_DEG);
        let pulse_usec = SERVO_MINIMUM_USEC
            + (SERVO_MAXIMUM_USEC - SERVO_MINIMUM_USEC) * angle / SERVO_RANGE_DEG;
        let off_count = (pulse_usec / PERIOD_USEC * COUNTS_PER_PERIOD).round() as u16;
        self.set_channel(channel, PULSE_START_COUNT, off_count)
    }
}
