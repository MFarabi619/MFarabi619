use oxidros::prelude::*;
use robot::{config::rover_config, hardware::motor::drivetrain};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let context = Context::new()?;
    robot::init_logging(&context, "gesture_pet")?;

    let drivetrain = drivetrain(robot::rover_chip()?)?;
    robot::spawn_sensors(&context)?;
    robot::spawn_robot_description(&context)?;

    let driver_node = context.create_node("base_controller", None)?;
    robot::spawn_logged(
        "driver",
        robot::run_driver(driver_node, drivetrain, rover_config()),
    );

    let pet_node = context.create_node("gesture_pet", None)?;
    robot::run_gesture_pet(pet_node).await
}
