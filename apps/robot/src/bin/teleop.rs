use oxidros::prelude::*;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    init_ros_logging("teleop");
    let context = Context::new()?;
    let node = context.create_node("teleop", None)?;
    robot::run_teleop(node)
}
