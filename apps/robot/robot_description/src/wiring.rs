// pub const HOST: &str = "rpi5-16-2";
pub const HOST: &str = "10.0.0.208";
pub const RGPIOD_PORT: u16 = 8889;
pub const GPIO_CHIP: u32 = 0;

pub const PWM_FREQUENCY_HZ: f32 = 10_000.0;
pub const MAX_LINEAR_VELOCITY_MPS: f64 = 2.0;

pub const LEFT_DIR_PIN: u32 = 6;
pub const LEFT_PWM_PIN: u32 = 12;
pub const LEFT_FORWARD_LEVEL: bool = true;

pub const RIGHT_DIR_PIN: u32 = 5;
pub const RIGHT_PWM_PIN: u32 = 13;
pub const RIGHT_FORWARD_LEVEL: bool = false;
