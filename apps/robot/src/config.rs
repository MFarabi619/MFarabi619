use crate::{driver::Config, hardware::motor::Shaping};

pub const HOST: &str = "rpi5-16-2";

pub const RGPIOD_PORT: u16 = 8889;
pub const GPIO_CHIP: u32 = 0;

pub const I2C_BUS: u32 = 1;
pub const PCA9685_ADDRESS: u32 = 0x40;

pub const BRIDGE_PORT: u16 = 8765;
pub const CAMERA_PORT: u16 = 8888;
pub const CAMERA: crate::camera::CameraProfile = crate::camera::ORBBEC_GEMINI_335L;

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
