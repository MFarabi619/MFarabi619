use oxidros::prelude::*;
use robot::config::rover_config;
use robot_drivers::motor::drivetrain;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    #[cfg(feature = "pixi")]
    robot::ensure_router().await?;

    let context = Context::new()?;
    robot::init_logging(&context, "base_controller")?;

    let drivetrain = drivetrain(robot::rover_chip()?)?;
    robot::spawn_sensors(&context)?;
    robot::spawn_robot_description(&context)?;

    match robot::rover_camera_mount() {
        Ok(servos) => {
            let mount_node = context.create_node("camera_mount", None)?;
            robot::spawn_logged("camera_mount", robot::run_camera_mount(mount_node, servos));
        }
        Err(error) => tracing::warn!("camera mount unavailable, driving without it: {error}"),
    }

    #[cfg(feature = "perception")]
    robot::spawn_perception(&context)?;

    let driver_node = context.create_node("base_controller", None)?;
    robot::run_driver(driver_node, drivetrain, rover_config()).await
}
