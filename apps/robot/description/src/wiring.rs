pub const RGPIOD_HOST: &str = "10.0.0.222";
pub const RGPIOD_PORT: u16 = 8889;
pub const GPIO_CHIP: u32 = 3;

pub const PWM_FREQUENCY_HZ: f32 = 20_000.0;
pub const MAX_LINEAR_VELOCITY_MPS: f64 = 2.0;

pub const LEFT_DIR_PIN: u32 = 7; // 36
pub const LEFT_PWM_PIN: u32 = 10; // 38
pub const LEFT_PWM_CHIP: u32 = 4;
pub const LEFT_PWM_CHANNEL: u32 = 1;
pub const LEFT_FORWARD_LEVEL: bool = true;

pub const RIGHT_DIR_PIN: u32 = 12; // 35
pub const RIGHT_PWM_PIN: u32 = 16; // 32
pub const RIGHT_PWM_CHIP: u32 = 3;
pub const RIGHT_PWM_CHANNEL: u32 = 1;
pub const RIGHT_FORWARD_LEVEL: bool = false;
