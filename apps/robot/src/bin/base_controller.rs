use oxidros::prelude::*;
use robot::config::{robot3_config, robot3_drivetrain};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    #[cfg(feature = "pixi")]
    robot::ensure_router().await?;

    init_ros_logging("base_controller");
    let context = Context::new()?;

    let drivetrain = robot3_drivetrain(robot::robot3_chip()?)?;

    #[cfg(feature = "perception")]
    robot::spawn_perception(&context)?;

    let driver_node = context.create_node("base_controller", None)?;
    robot::run_driver(driver_node, drivetrain, robot3_config()).await
}
