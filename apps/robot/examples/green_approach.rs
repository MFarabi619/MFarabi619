use oxidros::prelude::*;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let context = Context::new()?;
    robot::init_logging(&context, "green_approach")?;

    robot::spawn_rover_driver(&context)?;

    let approach_node = context.create_node("green_approach", None)?;
    robot::run_green_approach(approach_node).await
}
