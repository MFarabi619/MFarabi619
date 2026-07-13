use oxidros::prelude::*;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let context = Context::new()?;
    robot::init_logging(&context, "gesture_webcam")?;

    robot::spawn_bridge(&context)?;
    robot::spawn_robot_description(&context)?;

    let gesture_node = context.create_node("gesture_webcam", None)?;
    robot::run_gesture_pet(gesture_node).await
}
