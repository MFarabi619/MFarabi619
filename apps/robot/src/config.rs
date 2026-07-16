use crate::driver::Config;
use robot_drivers::motor::Shaping;

pub use robot_description::wiring::{GPIO_CHIP, HOST, RGPIOD_PORT};

pub const I2C_BUS: u32 = 1;
pub const PCA9685_ADDRESS: u32 = 0x40;

pub const BRIDGE_PORT: u16 = 8765;
pub const CAMERA_PORT: u16 = 8887;
pub const CAMERA: robot_sensors::CameraProfile = robot_sensors::ORBBEC_GEMINI_335L;

pub fn rover_config() -> Config {
    Config {
        host: HOST.to_string(),
        deadman_seconds: 0.5,
        shaping: Shaping {
            deadzone: 0.05,
            min_duty: 0.2,
            scale: 1.0,
        },
        publish_odometry: true,
    }
}
