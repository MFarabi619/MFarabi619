use oxidros::prelude::*;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let context = Context::new()?;
    robot::init_logging(&context, "road_sim")?;

    robot::spawn_bridge(&context)?;
    robot::spawn_robot_description(&context)?;

    let sim_node = context.create_node("simulator", None)?;
    robot::spawn_logged(
        "simulator",
        robot::run_simulator(sim_node, robot::Scene::Road),
    );

    let line_node = context.create_node("line_follower", None)?;
    robot::run_line_follower(line_node, robot::LineColor::White).await
}
