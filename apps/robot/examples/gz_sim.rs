use std::time::Duration;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

fn spawn(name: &'static str, command: &'static [&'static str]) {
    let argv: Vec<String> = command.iter().map(|part| part.to_string()).collect();
    tokio::spawn(async move {
        match robot::pixi::run(&argv, &[], None).await {
            Ok(status) => tracing::error!("{name} exited: {status}"),
            Err(error) => tracing::error!("{name} failed: {error}"),
        }
    });
}

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    tracing_subscriber::fmt::init();

    spawn("router", &["ros2", "run", "rmw_zenoh_cpp", "rmw_zenohd"]);
    tokio::time::sleep(Duration::from_secs(1)).await;

    spawn(
        "gz",
        &[
            "ros2",
            "launch",
            "ros_gz_sim",
            "gz_sim.launch.py",
            "gz_args:=-r empty.sdf",
        ],
    );
    spawn(
        "clock_bridge",
        &[
            "ros2",
            "run",
            "ros_gz_bridge",
            "parameter_bridge",
            "/clock@rosgraph_msgs/msg/Clock@gz.msgs.Clock",
        ],
    );

    std::future::pending::<()>().await;
    Ok(())
}
