use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use oxidros::{
    msg::{
        common_interfaces::{
            diagnostic_msgs::msg::{
                DiagnosticArray, DiagnosticStatus, DiagnosticStatusSeq, KeyValue, KeyValueSeq,
            },
            geometry_msgs::msg::Twist,
            std_msgs::msg::String as StringMsg,
        },
        msg::RosString,
    },
    prelude::*,
};
use tokio::time::interval;

use crate::{
    command_is_stale,
    hardware::motor::{mix, shape, Drivetrain, Shaping, HALT},
    latched_profile, now_stamp,
    odometry::Odometry,
};

const ROBOT_URDF: &str = include_str!("../urdf/robot.urdf");
const DEADMAN_TICK: Duration = Duration::from_millis(100);
const ODOMETRY_HZ: f64 = 30.0;
const DIAGNOSTICS_HZ: f64 = 1.0;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

pub struct Config {
    pub host: String,
    pub deadman_seconds: f64,
    pub shaping: Shaping,
    pub publish_odometry: bool,
}

fn diagnostics(host: &str, cmd_vel_age: f64, deadman_seconds: f64) -> DiagnosticArray {
    let (sec, nanosec) = now_stamp();
    let mut array = DiagnosticArray::new().unwrap();
    array.header.stamp.sec = sec;
    array.header.stamp.nanosec = nanosec;

    let mut rgpiod = DiagnosticStatus::new().unwrap();
    rgpiod.level = DiagnosticStatus::OK;
    rgpiod.name = RosString::new("rgpiod").unwrap();
    rgpiod.hardware_id = RosString::new(host).unwrap();
    rgpiod.message = RosString::new("connected").unwrap();

    let mut age_value = KeyValue::new().unwrap();
    age_value.key = RosString::new("age_seconds").unwrap();
    age_value.value = RosString::new(&format!("{cmd_vel_age:.2}")).unwrap();

    let mut cmd_vel = DiagnosticStatus::new().unwrap();
    cmd_vel.level = if command_is_stale(cmd_vel_age, deadman_seconds) {
        DiagnosticStatus::WARN
    } else {
        DiagnosticStatus::OK
    };
    cmd_vel.name = RosString::new("cmd_vel").unwrap();
    cmd_vel.hardware_id = RosString::new(host).unwrap();
    cmd_vel.message = RosString::new(&format!("{cmd_vel_age:.1}s since last command")).unwrap();
    cmd_vel.values = KeyValueSeq::<0>::from_vec(vec![age_value]).unwrap();

    array.status = DiagnosticStatusSeq::<0>::from_vec(vec![rgpiod, cmd_vel]).unwrap();
    array
}

pub async fn run_driver(
    node: Arc<Node>,
    drivetrain: Drivetrain<'_>,
    config: Config,
) -> Result<(), BoxError> {
    let mut cmd_vel = node.create_subscriber::<Twist>("cmd_vel", None)?;
    let diagnostics_pub = node.create_publisher::<DiagnosticArray>("/diagnostics", None)?;

    let _robot_description = if config.publish_odometry {
        let publisher =
            node.create_publisher::<StringMsg>("robot_description", Some(latched_profile()))?;
        let mut description = StringMsg::new().unwrap();
        description.data = RosString::new(ROBOT_URDF).unwrap();
        publisher.send(&description)?;
        Some(publisher)
    } else {
        None
    };
    let mut odometry = if config.publish_odometry {
        Some(Odometry::new(&node)?)
    } else {
        None
    };

    let mut last_command = Instant::now();
    let mut deadman = interval(DEADMAN_TICK);
    let mut odometry_tick = interval(Duration::from_secs_f64(1.0 / ODOMETRY_HZ));
    let mut diagnostics_tick = interval(Duration::from_secs_f64(1.0 / DIAGNOSTICS_HZ));

    tracing::info!("driving on cmd_vel via rgpiod at {}", config.host);
    let ctrl_c = tokio::signal::ctrl_c();
    tokio::pin!(ctrl_c);
    loop {
        tokio::select! {
            _ = &mut ctrl_c => break,
            message = cmd_vel.recv() => {
                let twist = message?.sample;
                drivetrain.drive(shape(mix(twist.linear.x, twist.angular.z), config.shaping))?;
                if let Some(odometry) = odometry.as_mut() {
                    odometry.set_command(twist.linear.x, twist.angular.z);
                }
                last_command = Instant::now();
            }
            _ = deadman.tick() => {
                if command_is_stale(last_command.elapsed().as_secs_f64(), config.deadman_seconds) {
                    drivetrain.drive(HALT)?;
                    if let Some(odometry) = odometry.as_mut() {
                        odometry.stop();
                    }
                }
            }
            _ = odometry_tick.tick() => {
                if let Some(odometry) = odometry.as_mut() {
                    odometry.publish()?;
                }
            }
            _ = diagnostics_tick.tick() => {
                let age = last_command.elapsed().as_secs_f64();
                diagnostics_pub.send(&diagnostics(&config.host, age, config.deadman_seconds))?;
            }
        }
    }

    tracing::info!("halting");
    drivetrain.drive(HALT)?;
    Ok(())
}
