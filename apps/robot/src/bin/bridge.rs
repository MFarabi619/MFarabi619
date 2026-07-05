use oxidros::prelude::*;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    init_ros_logging("bridge");
    let ctx = Context::new()?;
    let node = ctx.create_node("bridge", None)?;
    robot::run_bridge(node, 8765).await
}
