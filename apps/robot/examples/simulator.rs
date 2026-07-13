use oxidros::prelude::*;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let context = Context::new()?;
    robot::init_logging(&context, "simulator")?;
    let sim_node = context.create_node("simulator", None)?;
    robot::spawn_bridge(&context)?;
    robot::spawn_robot_description(&context)?;
    robot::run_simulator(sim_node, robot::Scene::Field).await
}
