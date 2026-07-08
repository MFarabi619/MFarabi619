use oxidros::prelude::*;
use robot::{
    hardware::{
        gpio::Connection,
        motor::{Drivetrain, Motor, Shaping},
    },
    Config,
};

const LEFT_PWM_PIN: u32 = 12;
const LEFT_DIR_PIN: u32 = 6;
const RIGHT_PWM_PIN: u32 = 13;
const RIGHT_DIR_PIN: u32 = 5;
const LEFT_FORWARD_LEVEL: bool = true;
const RIGHT_FORWARD_LEVEL: bool = false;
const PWM_FREQUENCY_HZ: f32 = 1000.0;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let context = Context::new()?;
    robot::init_logging(&context, "cytron_md30c")?;

    let connection = Connection::connect("rpi5-16-2", 8889)?;
    let chip = connection.open_chip(0)?;
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

    robot::spawn_bridge(&context)?;

    let driver_node = context.create_node("cytron_md30c", None)?;
    robot::run_driver(
        driver_node,
        drivetrain,
        Config {
            host: "rpi5-16-2".to_string(),
            deadman_seconds: 0.5,
            shaping: Shaping {
                deadzone: 0.05,
                min_duty: 0.35,
                scale: 0.5,
            },
            publish_odometry: true,
        },
    )
    .await
}
