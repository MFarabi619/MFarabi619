use std::sync::Arc;

use oxidros::{msg::common_interfaces::geometry_msgs::msg::Vector3, prelude::*};

use crate::config;
use robot_drivers::{gpio::Connection, i2c::I2c, pca9685::Pca9685};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const PAN_CHANNEL: u8 = 1;
const TILT_CHANNEL: u8 = 0;
const CENTER_DEG: f64 = 90.0;
const MINIMUM_DEG: f64 = 0.0;
const MAXIMUM_DEG: f64 = 180.0;

pub fn rover_camera_mount() -> Result<Pca9685<'static>, BoxError> {
    let connection: &'static Connection = Box::leak(Box::new(Connection::connect(
        config::HOST,
        config::RGPIOD_PORT,
    )?));
    let i2c = I2c::open(connection, config::I2C_BUS, config::PCA9685_ADDRESS)?;
    Ok(Pca9685::new(i2c)?)
}

pub async fn run_camera_mount(node: Arc<Node>, servos: Pca9685<'static>) -> Result<(), BoxError> {
    let mut command =
        node.create_subscriber::<Vector3>("camera/command", Some(Profile { depth: 1, ..Profile::sensor_data() }))?;
    servos.set_servo_angle(PAN_CHANNEL, CENTER_DEG)?;
    servos.set_servo_angle(TILT_CHANNEL, CENTER_DEG)?;
    tracing::info!("aiming camera on camera/command (x=pan, y=tilt)");
    loop {
        let target = command.recv().await?.sample;
        servos.set_servo_angle(PAN_CHANNEL, target.x.clamp(MINIMUM_DEG, MAXIMUM_DEG))?;
        servos.set_servo_angle(TILT_CHANNEL, target.y.clamp(MINIMUM_DEG, MAXIMUM_DEG))?;
    }
}
