use oxidros::prelude::*;
use robot::{config::rover_config, hardware::motor::drivetrain};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let context = Context::new()?;
    robot::init_logging(&context, "base_controller")?;

    let drivetrain = drivetrain(robot::rover_chip()?)?;
    robot::spawn_sensors(&context)?;
    robot::spawn_robot_description(&context)?;

    let driver_node = context.create_node("base_controller", None)?;
    robot::run_driver(driver_node, drivetrain, rover_config()).await
}
