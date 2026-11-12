use rattler_conda_types::Platform;

type BoxError = Box<dyn std::error::Error + Send + Sync>;

struct Task {
    name: &'static str,
    command: &'static [&'static str],
    working_directory:Option<&'static str>,
    environment: &'static [(&'static str, &'static str)],
    platform: Option<Platform>,
}

const TASKS: &[Task] = &[
    Task {
        name: "rviz",
        command: &["rviz2"],
        working_directory:None,
        environment: &[],
        platform: None,
    },
    Task {
        name: "graph",
        command: &["rqt_graph"],
        working_directory:None,
        environment: &[],
        platform: None,
    },
    Task {
        name: "turtlesim_node",
        command: &["ros2", "run", "turtlesim", "turtlesim_node"],
        working_directory:None,
        environment: &[],
        platform: None,
    },
    Task {
        name: "turtlesim_teleop",
        command: &["ros2", "run", "turtlesim", "turtle_teleop_key"],
        working_directory:None,
        environment: &[],
        platform: None,
    },
    Task {
        name: "teleop",
        command: &[
            "ros2",
            "run",
            "teleop_twist_keyboard",
            "teleop_twist_keyboard",
        ],
        working_directory:None,
        environment: &[],
        platform: None,
    },
    Task {
        name: "cad",
        command: &["python", "main.py"],
        working_directory:Some("apps/robot/src/bin/cad"),
        environment: &[("YACV_HOST", "127.0.0.1"), ("YACV_PORT", "32323")],
        platform: Some(Platform::OsxArm64),
    },
];

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let name = std::env::args().nth(1).ok_or("usage: task <name>")?;
    let task = TASKS
        .iter()
        .find(|task| task.name == name)
        .ok_or_else(|| format!("unknown task '{name}'"))?;
    if let Some(platform) = task.platform {
        if platform != Platform::current() {
            return Err(format!("task '{name}' is only available on {platform}").into());
        }
    }

    let command: Vec<String> = task.command.iter().map(|part| part.to_string()).collect();
    let status = robot::pixi::run(&command, task.environment, task.working_directory).await?;
    std::process::exit(status.code().unwrap_or(1));
}
