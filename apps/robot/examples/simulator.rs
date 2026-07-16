use oxidros::prelude::*;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let context = Context::new()?;
    robot::init_logging(&context, "simulator")?;

    robot::spawn_bridge(&context)?;
    robot::spawn_robot_description(&context)?;

    let sim_node = context.create_node("simulator", None)?;
    robot::spawn_logged(
        "simulator",
        robot_simulator::run_simulator(sim_node, robot_simulator::Scene::Field),
    );

    let line_node = context.create_node("line_follower", None)?;
    robot::spawn_logged(
        "line_follower",
        robot::run_line_follower(line_node, robot::LineColor::White, false),
    );

    let row_node = context.create_node("row_follower", None)?;
    robot::spawn_logged("row_follower", robot::run_row_follower(row_node, false));

    let gesture_node = context.create_node("gesture", None)?;
    robot::run_gesture(gesture_node, false).await
}
