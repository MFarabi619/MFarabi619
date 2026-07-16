use std::time::Duration;

use oxidros::prelude::*;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const ROBOT_URDF: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/robot_description/urdf/robot.urdf");
const PACKAGE_ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/..");

fn spawn(
    name: &'static str,
    command: &'static [&'static str],
    env: &'static [(&'static str, &'static str)],
) {
    let argv: Vec<String> = command.iter().map(|part| part.to_string()).collect();
    tokio::spawn(async move {
        match robot::pixi::run(&argv, env, None).await {
            Ok(status) => tracing::error!("{name} exited: {status}"),
            Err(error) => tracing::error!("{name} failed: {error}"),
        }
    });
}

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let context = Context::new()?;
    robot::init_logging(&context, "gazebo")?;

    spawn("router", &["ros2", "run", "rmw_zenoh_cpp", "rmw_zenohd"], &[]);
    tokio::time::sleep(Duration::from_secs(1)).await;

    robot::spawn_bridge(&context)?;
    robot::spawn_robot_description(&context)?;

    spawn(
        "gz",
        &[
            "ros2",
            "launch",
            "ros_gz_sim",
            "gz_sim.launch.py",
            "gz_args:=-r empty.sdf",
        ],
        &[],
    );
    tokio::time::sleep(Duration::from_secs(3)).await;

    spawn(
        "spawn_robot",
        &[
            "ros2", "run", "ros_gz_sim", "create", "-world", "empty", "-name", "robot", "-z",
            "0.4", "-file", ROBOT_URDF,
        ],
        &[("GZ_SIM_RESOURCE_PATH", PACKAGE_ROOT)],
    );

    spawn(
        "bridge",
        &[
            "ros2",
            "run",
            "ros_gz_bridge",
            "parameter_bridge",
            "/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock",
            "/cmd_vel@geometry_msgs/msg/Twist]gz.msgs.Twist",
            "/odom@nav_msgs/msg/Odometry[gz.msgs.Odometry",
            "/tf@tf2_msgs/msg/TFMessage[gz.msgs.Pose_V",
            "/joint_states@sensor_msgs/msg/JointState[gz.msgs.Model",
        ],
        &[],
    );

    std::future::pending::<()>().await;
    Ok(())
}
