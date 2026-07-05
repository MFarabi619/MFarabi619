use oxidros::prelude::*;

const BRIDGE_PORT: u16 = 8765;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    init_ros_logging("simulator");
    let ctx = Context::new()?;
    let sim_node = ctx.create_node("simulator", None)?;
    let bridge_node = ctx.create_node("bridge", None)?;
    tokio::spawn(robot::run_bridge(bridge_node, BRIDGE_PORT));
    robot::run_simulator(sim_node).await
}
