use std::time::Duration;

use oxidros::prelude::*;
use robot::Config;
use robot_drivers::{
    gpio::Connection,
    motor::{Drivetrain, Motor, Shaping},
    servo::Servo,
    ws2812::{LedStrip, GREEN},
};

const RGPIOD_HOST: &str = "rpi5-16";
const RGPIOD_PORT: u16 = 8889;
const CAMERA_PORT: &str = "8888";
const GPIO_CHIP: u32 = 0;
const PWM_FREQUENCY_HZ: f32 = 1000.0;
const SERVO_FREQUENCY_HZ: f32 = 50.0;

const LEFT_FORWARD_PIN: u32 = 24;
const LEFT_BACKWARD_PIN: u32 = 23;
const RIGHT_FORWARD_PIN: u32 = 5;
const RIGHT_BACKWARD_PIN: u32 = 6;
const ARM_LIFT_PIN: u32 = 12;
const ARM_GRIPPER_PIN: u32 = 13;

const ARM_LIFT_RAISED_DEG: f64 = 150.0;
const ARM_GRIPPER_HOME_DEG: f64 = 140.0;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    init_ros_logging("freenove_fnk0077");
    let context = Context::new()?;

    let connection = Connection::connect(RGPIOD_HOST, RGPIOD_PORT)?;
    let chip = connection.open_chip(GPIO_CHIP)?;
    let drivetrain = Drivetrain::new(
        Motor::dual_pwm(&chip, LEFT_FORWARD_PIN, LEFT_BACKWARD_PIN, PWM_FREQUENCY_HZ)?,
        Motor::dual_pwm(&chip, RIGHT_FORWARD_PIN, RIGHT_BACKWARD_PIN, PWM_FREQUENCY_HZ)?,
    );

    Servo::new(&chip, ARM_LIFT_PIN, SERVO_FREQUENCY_HZ)?.angle(ARM_LIFT_RAISED_DEG)?;
    Servo::new(&chip, ARM_GRIPPER_PIN, SERVO_FREQUENCY_HZ)?.angle(ARM_GRIPPER_HOME_DEG)?;

    let mut leds = LedStrip::open(&connection)?;
    leds.color_wipe(GREEN, Duration::from_millis(120))?;

    let camera_node = context.create_node("camera", None)?;
    robot::spawn_logged(
        "camera",
        robot::run_camera(camera_node, format!("{RGPIOD_HOST}:{CAMERA_PORT}"), robot::config::CAMERA),
    );

    robot::spawn_bridge(&context)?;
    robot::spawn_robot_description(&context)?;

    let driver_node = context.create_node("freenove_fnk0077", None)?;
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
