use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use oxidros::{
    msg::{
        common_interfaces::{geometry_msgs::msg::Twist, sensor_msgs::msg::JointState},
        msg::RosStringSeq,
    },
    prelude::*,
};
use robot_description::time::now_stamp;

use crate::config;
use robot_drivers::{gpio::Connection, i2c::I2c, pca9685::Pca9685};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const PAN_CHANNEL: u8 = 1;
const TILT_CHANNEL: u8 = 0;
const PAN_CENTER_DEG: f64 = 90.0;
const TILT_CENTER_DEG: f64 = 180.0;
const TRAVEL_RAD: f64 = std::f64::consts::FRAC_PI_2;
const PAN_JOINT: &str = "ptu_0_pan";
const TILT_JOINT: &str = "ptu_0_tilt";
const COMMAND_TOPIC: &str = "sensors/ptu_0/cmd";
const VELOCITY_TOPIC: &str = "sensors/ptu_0/cmd_vel";
const STATE_TOPIC: &str = "joint_states";
const CONTROL_HZ: f64 = 20.0;
const COMMAND_TIMEOUT: f64 = 0.5;

fn servo_degrees(center_deg: f64, radians: f64) -> f64 {
    (center_deg + radians.to_degrees()).clamp(0.0, 180.0)
}

fn aim(servos: &Pca9685, pan_radians: f64, tilt_radians: f64) -> Result<(), BoxError> {
    servos.set_servo_angle(PAN_CHANNEL, servo_degrees(PAN_CENTER_DEG, pan_radians))?;
    servos.set_servo_angle(TILT_CHANNEL, servo_degrees(TILT_CENTER_DEG, tilt_radians))?;
    Ok(())
}

fn ptu_joint_state(pan_radians: f64, tilt_radians: f64) -> JointState {
    let (sec, nanosec) = now_stamp();
    let mut message = JointState::new().unwrap();
    message.header.stamp.sec = sec;
    message.header.stamp.nanosec = nanosec;
    let mut names = RosStringSeq::<0, 0>::new(2).unwrap();
    names.as_mut_slice()[0].assign(PAN_JOINT);
    names.as_mut_slice()[1].assign(TILT_JOINT);
    message.name = names;
    message.position = [pan_radians, tilt_radians].as_slice().try_into().unwrap();
    message
}

pub fn rover_camera_mount() -> Result<Pca9685<'static>, BoxError> {
    let connection: &'static Connection = Box::leak(Box::new(Connection::connect(
        config::RGPIOD_HOST,
        config::RGPIOD_PORT,
    )?));
    let i2c = I2c::open(connection, config::I2C_BUS, config::PCA9685_ADDRESS)?;
    Ok(Pca9685::new(i2c)?)
}

pub async fn run_camera_mount(node: Arc<Node>, servos: Pca9685<'static>) -> Result<(), BoxError> {
    let mut command = node.create_subscriber::<JointState>(
        COMMAND_TOPIC,
        Some(Profile { depth: 1, ..Profile::sensor_data() }),
    )?;
    let mut velocity = node.create_subscriber::<Twist>(
        VELOCITY_TOPIC,
        Some(Profile { depth: 1, ..Profile::sensor_data() }),
    )?;
    let state = node.create_publisher::<JointState>(STATE_TOPIC, None)?;

    let mut pan_radians = 0.0;
    let mut tilt_radians = 0.0;
    let mut pan_rate = 0.0;
    let mut tilt_rate = 0.0;
    let mut last_velocity = Instant::now();
    aim(&servos, pan_radians, tilt_radians)?;

    let mut tick = tokio::time::interval(Duration::from_secs_f64(1.0 / CONTROL_HZ));
    tracing::info!("aiming camera: {COMMAND_TOPIC} (JointState) + {VELOCITY_TOPIC} (Twist)");
    loop {
        tokio::select! {
            message = command.recv() => {
                let joint_state = message?.sample;
                for (name, position) in joint_state.name.iter().zip(joint_state.position.iter()) {
                    let clamped = (*position).clamp(-TRAVEL_RAD, TRAVEL_RAD);
                    if name.get_string() == PAN_JOINT {
                        pan_radians = clamped;
                    } else if name.get_string() == TILT_JOINT {
                        tilt_radians = clamped;
                    }
                }
                pan_rate = 0.0;
                tilt_rate = 0.0;
                aim(&servos, pan_radians, tilt_radians)?;
            }
            message = velocity.recv() => {
                let twist = message?.sample;
                pan_rate = twist.angular.z;
                tilt_rate = twist.linear.x;
                last_velocity = Instant::now();
            }
            _ = tick.tick() => {
                if last_velocity.elapsed().as_secs_f64() > COMMAND_TIMEOUT {
                    pan_rate = 0.0;
                    tilt_rate = 0.0;
                }
                if pan_rate != 0.0 || tilt_rate != 0.0 {
                    let dt = 1.0 / CONTROL_HZ;
                    pan_radians = (pan_radians + pan_rate * dt).clamp(-TRAVEL_RAD, TRAVEL_RAD);
                    tilt_radians = (tilt_radians + tilt_rate * dt).clamp(-TRAVEL_RAD, TRAVEL_RAD);
                    aim(&servos, pan_radians, tilt_radians)?;
                }
                state.send(&ptu_joint_state(pan_radians, tilt_radians))?;
            }
        }
    }
}
