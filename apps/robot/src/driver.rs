use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use oxidros::{
    msg::common_interfaces::{
        diagnostic_msgs::msg::{DiagnosticArray, DiagnosticStatus},
        geometry_msgs::msg::Twist,
    },
    prelude::*,
};
use tokio::time::interval;

use crate::{
    diagnostics::{diagnostic_array, Status},
    hardware::motor::{mix, shape, Drivetrain, Shaping, Velocity, HALT},
    odometry::Odometry,
    qos,
    ruckig_profile::{AxisLimits, RuckigProfile},
};

const CONTROL_HZ: f64 = 50.0;
const ODOMETRY_HZ: f64 = 30.0;
const DIAGNOSTICS_HZ: f64 = 1.0;

const LINEAR_MAX_ACCELERATION: f64 = 8.0;
const LINEAR_MAX_JERK: f64 = 60.0;
const ANGULAR_MAX_ACCELERATION: f64 = 10.0;
const ANGULAR_MAX_JERK: f64 = 70.0;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

pub struct Config {
    pub host: String,
    pub deadman_seconds: f64,
    pub shaping: Shaping,
    pub publish_odometry: bool,
}

fn diagnostics(host: &str, cmd_vel_age_seconds: f64, deadman_seconds: f64) -> DiagnosticArray {
    let cmd_vel_level = if command_is_stale(cmd_vel_age_seconds, deadman_seconds) {
        DiagnosticStatus::WARN
    } else {
        DiagnosticStatus::OK
    };
    diagnostic_array(vec![
        Status::new(DiagnosticStatus::OK, "rgpiod", host).message("connected"),
        Status::new(cmd_vel_level, "cmd_vel", host)
            .message(&format!("{cmd_vel_age_seconds:.1}s since last command"))
            .value("age_seconds", &format!("{cmd_vel_age_seconds:.2}")),
    ])
}

pub async fn run_driver(
    node: Arc<Node>,
    drivetrain: Drivetrain<'_>,
    config: Config,
) -> Result<(), BoxError> {
    let mut cmd_vel = node.create_subscriber::<Twist>("cmd_vel", Some(qos::command()))?;
    let diagnostics_pub = node.create_publisher::<DiagnosticArray>("/diagnostics", None)?;

    let mut odometry = if config.publish_odometry {
        Some(Odometry::new(&node)?)
    } else {
        None
    };

    let mut target_linear = 0.0;
    let mut target_angular = 0.0;
    let control_dt = 1.0 / CONTROL_HZ;
    let mut profile = RuckigProfile::new(
        control_dt,
        AxisLimits {
            max_acceleration: LINEAR_MAX_ACCELERATION,
            max_jerk: LINEAR_MAX_JERK,
        },
        AxisLimits {
            max_acceleration: ANGULAR_MAX_ACCELERATION,
            max_jerk: ANGULAR_MAX_JERK,
        },
    );

    let mut last_command = Instant::now();
    let mut last_written: Option<Velocity> = None;
    let mut control = interval(Duration::from_secs_f64(control_dt));
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
                target_linear = twist.linear.x;
                target_angular = twist.angular.z;
                last_command = Instant::now();
            }
            _ = control.tick() => {
                let output = if command_is_stale(last_command.elapsed().as_secs_f64(), config.deadman_seconds) {
                    // Comms lost: hard stop and forget stored motion — a safety halt must not ease out.
                    profile.reset();
                    target_linear = 0.0;
                    target_angular = 0.0;
                    if let Some(odometry) = odometry.as_mut() {
                        odometry.stop();
                    }
                    HALT
                } else {
                    let (linear, angular) = profile.step(target_linear, target_angular);
                    if let Some(odometry) = odometry.as_mut() {
                        odometry.set_velocity_command(linear, angular);
                    }
                    shape(mix(linear, angular), config.shaping)
                };
                if last_written != Some(output) {
                    drivetrain.drive(output)?;
                    last_written = Some(output);
                }
            }
            _ = odometry_tick.tick() => {
                if let Some(odometry) = odometry.as_mut() {
                    odometry.publish()?;
                }
            }
            _ = diagnostics_tick.tick() => {
                let age_seconds = last_command.elapsed().as_secs_f64();
                diagnostics_pub.send(&diagnostics(
                    &config.host,
                    age_seconds,
                    config.deadman_seconds,
                ))?;
            }
        }
    }

    tracing::info!("halting");
    drivetrain.drive(HALT)?;
    Ok(())
}

pub fn command_is_stale(age_seconds: f64, threshold_seconds: f64) -> bool {
    age_seconds > threshold_seconds
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fresh_command_is_not_stale() {
        assert!(!command_is_stale(0.5, 2.0));
    }

    #[test]
    fn old_command_is_stale() {
        assert!(command_is_stale(3.0, 2.0));
    }
}
