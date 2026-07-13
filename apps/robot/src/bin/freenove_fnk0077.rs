use std::time::Duration;

use oxidros::prelude::*;
use robot::{
    hardware::{
        gpio::Connection,
        motor::{Drivetrain, Motor, Shaping},
        servo::Servo,
        ws2812::{LedStrip, GREEN},
    },
    Config,
};

const HOST: &str = "rpi5-16";
const PWM_FREQUENCY_HZ: f32 = 1000.0;
const SERVO_FREQUENCY_HZ: f32 = 50.0;
const ARM_LIFT_RAISED_DEG: f64 = 150.0;
const ARM_GRIPPER_HOME_DEG: f64 = 140.0;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    init_ros_logging("freenove_fnk0077");
    let context = Context::new()?;

    let connection = Connection::connect(HOST, 8889)?;
    let chip = connection.open_chip(0)?;
    let drivetrain = Drivetrain::new(
        Motor::dual_pwm(&chip, 24, 23, PWM_FREQUENCY_HZ)?,
        Motor::dual_pwm(&chip, 5, 6, PWM_FREQUENCY_HZ)?,
    );

    Servo::new(&chip, 12, SERVO_FREQUENCY_HZ)?.angle(ARM_LIFT_RAISED_DEG)?;
    Servo::new(&chip, 13, SERVO_FREQUENCY_HZ)?.angle(ARM_GRIPPER_HOME_DEG)?;

    let mut leds = LedStrip::open(&connection)?;
    leds.color_wipe(GREEN, Duration::from_millis(120))?;

    let camera_node = context.create_node("camera", None)?;
    robot::spawn_logged(
        "camera",
        robot::run_camera(camera_node, format!("{HOST}:8888"), robot::config::CAMERA),
    );

    robot::spawn_bridge(&context)?;
    robot::spawn_robot_description(&context)?;

    let driver_node = context.create_node("freenove_fnk0077", None)?;
    robot::run_driver(
        driver_node,
        drivetrain,
        Config {
            host: HOST.to_string(),
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
