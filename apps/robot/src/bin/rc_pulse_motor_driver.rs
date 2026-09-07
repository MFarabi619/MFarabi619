use std::{
    path::Path,
    time::{Duration, Instant},
};

use oxidros::prelude::*;
use tokio::time::interval;

use robot::{
    driver::command_is_stale,
    platform_msgs::robot_platform_msgs::msg::{Drive, Feedback},
};
use robot_control::parameters::{bool_parameter, f64_parameter, i64_parameter};
use robot_drivers::sysfs_pwm::PulseChannel;

const SYSFS_PWM_ROOT: &str = "/sys/class/pwm";
const FEEDBACK_RATE_HZ: f64 = 50.0;
const COMMAND_TIMEOUT_SECONDS: f64 = 0.5;
const DEFAULT_MAX_WHEEL_SPEED: f64 = 1.0;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

struct Wheel {
    channel: PulseChannel,
    command_fraction: f64,
    velocity: f64,
    travel: f64,
}

impl Wheel {
    fn new(channel: PulseChannel) -> Self {
        Self {
            channel,
            command_fraction: 0.0,
            velocity: 0.0,
            travel: 0.0,
        }
    }

    fn drive(&mut self, wheel_speed: f64, max_wheel_speed: f64) -> std::io::Result<()> {
        self.command_fraction = self.channel.drive(wheel_speed / max_wheel_speed)?;
        self.velocity = wheel_speed;
        Ok(())
    }

    fn halt(&mut self) -> std::io::Result<()> {
        self.channel.halt()?;
        self.command_fraction = 0.0;
        self.velocity = 0.0;
        Ok(())
    }
}

fn feedback(wheels: &mut [Wheel; 2], commanded_mode: i8, has_timed_out: bool) -> Feedback {
    let (sec, nanosec) = oxidros::clock::Clock::new()
        .unwrap()
        .get_now()
        .map(|now| (now.as_secs() as i32, now.subsec_nanos()))
        .unwrap_or_default();
    let mut message = Feedback::default();
    message.header.stamp.sec = sec;
    message.header.stamp.nanosec = nanosec;
    message.commanded_mode = commanded_mode;
    message.actual_mode = if has_timed_out {
        Drive::MODE_NONE
    } else {
        commanded_mode
    };
    for (wheel, driver) in wheels.iter_mut().zip(message.drivers.iter_mut()) {
        wheel.travel += wheel.velocity / FEEDBACK_RATE_HZ;
        driver.duty_cycle = wheel.command_fraction as f32;
        driver.measured_velocity = wheel.velocity as f32;
        driver.measured_travel = wheel.travel as f32;
    }
    message
}

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    init_ros_logging("rc_pulse_motor_driver");
    let context = Context::new()?;
    let node = context.create_node("rc_pulse_motor_driver", None)?;

    let (max_wheel_speed, channel_settings) = {
        let parameters = node.create_parameter_server()?;
        let store = parameters.params.read();
        (
            f64_parameter(&store, "max_wheel_speed", DEFAULT_MAX_WHEEL_SPEED),
            ["left", "right"].map(|side| {
                (
                    i64_parameter(&store, &format!("{side}_pwm_chip"), 0) as u32,
                    i64_parameter(&store, &format!("{side}_pwm_channel"), 0) as u32,
                    bool_parameter(&store, &format!("{side}_reversed"), false),
                )
            }),
        )
    };

    let sysfs_root = Path::new(SYSFS_PWM_ROOT);
    let mut wheels = [
        Wheel::new(PulseChannel::new(
            sysfs_root,
            channel_settings[0].0,
            channel_settings[0].1,
            channel_settings[0].2,
        )?),
        Wheel::new(PulseChannel::new(
            sysfs_root,
            channel_settings[1].0,
            channel_settings[1].1,
            channel_settings[1].2,
        )?),
    ];

    let mut cmd_drive =
        node.create_subscriber::<Drive>("platform/motors/cmd_drive", Some(Profile::sensor_data()))?;
    let feedback_publisher =
        node.create_publisher::<Feedback>("platform/motors/feedback", Some(Profile::sensor_data()))?;

    let mut commanded_mode = Drive::MODE_NONE;
    let mut last_command = Instant::now();
    let mut feedback_tick = interval(Duration::from_secs_f64(1.0 / FEEDBACK_RATE_HZ));
    tracing::info!("driving ESC pulses via {SYSFS_PWM_ROOT}");
    let ctrl_c = tokio::signal::ctrl_c();
    tokio::pin!(ctrl_c);
    loop {
        tokio::select! {
            _ = &mut ctrl_c => break,
            message = cmd_drive.recv() => {
                let command = message?.sample;
                last_command = Instant::now();
                commanded_mode = command.mode;
                match command.mode {
                    Drive::MODE_VELOCITY => {
                        for (wheel, wheel_speed) in wheels.iter_mut().zip(command.drivers) {
                            wheel.drive(wheel_speed as f64, max_wheel_speed)?;
                        }
                    }
                    Drive::MODE_PWM => {
                        for (wheel, fraction) in wheels.iter_mut().zip(command.drivers) {
                            wheel.drive(fraction as f64 * max_wheel_speed, max_wheel_speed)?;
                        }
                    }
                    _ => {
                        for wheel in &mut wheels {
                            wheel.halt()?;
                        }
                    }
                }
            }
            _ = feedback_tick.tick() => {
                let has_timed_out = command_is_stale(
                    last_command.elapsed().as_secs_f64(), COMMAND_TIMEOUT_SECONDS);
                if has_timed_out {
                    for wheel in &mut wheels {
                        wheel.halt()?;
                    }
                }
                feedback_publisher.send(&feedback(&mut wheels, commanded_mode, has_timed_out))?;
            }
        }
    }

    for wheel in &mut wheels {
        wheel.halt()?;
    }
    Ok(())
}
