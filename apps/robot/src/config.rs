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

pub const LEFT_DIR_PIN: u32 = 7; // 36
pub const LEFT_PWM_PIN: u32 = 10; // 38
pub const LEFT_FORWARD_LEVEL: bool = true;

pub const RIGHT_DIR_PIN: u32 = 12; // 35
pub const RIGHT_PWM_PIN: u32 = 16; // 32
pub const RIGHT_FORWARD_LEVEL: bool = false;

pub fn robot3_drivetrain<'a>(chip: &'a Chip<'a>) -> Result<Drivetrain<'a>, Error> {
    Ok(Drivetrain::new(
        Motor::pwm_dir(chip, LEFT_DIR_PIN, LEFT_PWM_PIN, LEFT_FORWARD_LEVEL, PWM_FREQUENCY_HZ)?,
        Motor::pwm_dir(
            chip,
            RIGHT_DIR_PIN,
            RIGHT_PWM_PIN,
            RIGHT_FORWARD_LEVEL,
            PWM_FREQUENCY_HZ,
        )?,
    ))
}

pub fn robot3_config() -> Config {
    Config {
        host: RGPIOD_HOST.to_string(),
        deadman_seconds: 0.5,
        shaping: Shaping {
            deadzone: 0.05,
            min_duty: 0.2,
            scale: 1.0,
        },
        publish_odometry: true,
    }
}
