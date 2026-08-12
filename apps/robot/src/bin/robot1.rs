use oxidros::prelude::*;
use robot::Config;
use robot_drivers::{
    gpio::Connection,
    motor::{Drivetrain, Motor, Shaping},
};

const RGPIOD_HOST: &str = "rpi5-16-2";
const RGPIOD_PORT: u16 = 8889;
const GPIO_CHIP: u32 = 0;
const PWM_FREQUENCY_HZ: f32 = 1000.0;

const LEFT_DIR_PIN: u32 = 26;
const LEFT_PWM_PIN: u32 = 12;
const LEFT_FORWARD_LEVEL: bool = true;
const RIGHT_DIR_PIN: u32 = 24;
const RIGHT_PWM_PIN: u32 = 13;
const RIGHT_FORWARD_LEVEL: bool = false;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    init_ros_logging("robot1");
    let context = Context::new()?;

    let connection = Connection::connect(RGPIOD_HOST, RGPIOD_PORT)?;
    let chip = connection.open_chip(GPIO_CHIP)?;
    let drivetrain = Drivetrain::new(
        Motor::pwm_dir(
            &chip,
            LEFT_DIR_PIN,
            LEFT_PWM_PIN,
            LEFT_FORWARD_LEVEL,
            PWM_FREQUENCY_HZ,
        )?,
        Motor::pwm_dir(
            &chip,
            RIGHT_DIR_PIN,
            RIGHT_PWM_PIN,
            RIGHT_FORWARD_LEVEL,
            PWM_FREQUENCY_HZ,
        )?,
    );

    let driver_node = context.create_node("robot1", None)?;
    robot::run_driver(
        driver_node,
        drivetrain,
        Config {
            host: RGPIOD_HOST.to_string(),
            deadman_seconds: 0.5,
            shaping: Shaping {
                deadzone: 0.05,
                min_duty: 0.35,
                scale: 1.0,
            },
            publish_odometry: true,
        },
    )
    .await
}
