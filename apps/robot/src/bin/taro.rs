use std::path::Path;

use oxidros::prelude::*;
use robot::Config;
use robot_drivers::{
    motor::Shaping,
    sysfs_pwm::{PulseChannel, PulseDrivetrain},
};

const SYSFS_PWM_ROOT: &str = "/sys/class/pwm";
const PWM_CHIP: u32 = 0;
const LEFT_PWM_CHANNEL: u32 = 0;
const RIGHT_PWM_CHANNEL: u32 = 1;
const LEFT_REVERSED: bool = false;
const RIGHT_REVERSED: bool = false;
const MAX_SPEED_MPS: f64 = 2.0;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    init_ros_logging("taro");
    let context = Context::new()?;

    let sysfs_root = Path::new(SYSFS_PWM_ROOT);
    let drivetrain = PulseDrivetrain::new(
        PulseChannel::new(sysfs_root, PWM_CHIP, LEFT_PWM_CHANNEL, LEFT_REVERSED)?,
        PulseChannel::new(sysfs_root, PWM_CHIP, RIGHT_PWM_CHANNEL, RIGHT_REVERSED)?,
        MAX_SPEED_MPS,
    );

    let driver_node = context.create_node("base_controller", None)?;
    robot::run_driver(
        driver_node,
        drivetrain,
        Config {
            host: SYSFS_PWM_ROOT.to_string(),
            deadman_seconds: 0.5,
            shaping: Shaping {
                deadzone: 0.05,
                min_duty: 0.0,
                scale: 1.0,
            },
            publish_odometry: true,
        },
    )
    .await
}
