use crate::driver::Config;
use robot_drivers::{
    gpio::{Chip, Error},
    motor::{Drivetrain, Motor, Shaping},
};

pub const RGPIOD_HOST: &str = "10.0.0.222";
pub const RGPIOD_PORT: u16 = 8889;
pub const GPIO_CHIP: u32 = 3;

pub const I2C_BUS: u32 = 1;
pub const PCA9685_ADDRESS: u32 = 0x40;

pub const PWM_FREQUENCY_HZ: f32 = 20_000.0;

pub const LEFT_DIR_LINE: u32 = 7;
pub const LEFT_PWM_LINE: u32 = 10;
pub const LEFT_FORWARD_LEVEL: bool = true;

pub const RIGHT_DIR_LINE: u32 = 12;
pub const RIGHT_PWM_LINE: u32 = 16;
pub const RIGHT_FORWARD_LEVEL: bool = false;

pub fn beagleyai_drivetrain<'a>(chip: &'a Chip<'a>) -> Result<Drivetrain<'a>, Error> {
    Ok(Drivetrain::new(
        Motor::pwm_dir(
            chip,
            LEFT_DIR_LINE,
            LEFT_PWM_LINE,
            LEFT_FORWARD_LEVEL,
            PWM_FREQUENCY_HZ,
        )?,
        Motor::pwm_dir(
            chip,
            RIGHT_DIR_LINE,
            RIGHT_PWM_LINE,
            RIGHT_FORWARD_LEVEL,
            PWM_FREQUENCY_HZ,
        )?,
    ))
}

pub fn beagleyai_config() -> Config {
    Config {
        hardware_id: RGPIOD_HOST.to_string(),
        deadman_seconds: 0.5,
        shaping: Shaping {
            deadzone_fraction: 0.05,
            min_duty_fraction: 0.2,
            scale_factor: 1.0,
        },
        publish_odometry: true,
    }
}
