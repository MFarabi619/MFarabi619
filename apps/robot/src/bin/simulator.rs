use oxidros::prelude::*;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    init_ros_logging("simulator");
    let context = Context::new()?;
    let sim_node = context.create_node("simulator", None)?;
    robot::spawn_bridge(&context)?;
    robot::run_simulator(sim_node).await
}
