use oxidros::prelude::*;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let context = Context::new()?;
    robot::init_logging(&context, "line_follow")?;

    robot::spawn_rover_driver(&context)?;

    let line_node = context.create_node("line_follower", None)?;
    robot::run_line_follower(line_node, robot::LineColor::White).await
}
