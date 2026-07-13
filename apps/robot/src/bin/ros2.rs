type BoxError = Box<dyn std::error::Error + Send + Sync>;

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let mut command = vec!["ros2".to_string()];
    command.extend(std::env::args().skip(1));
    let status = robot::pixi::run(&command, &[], None).await?;
    std::process::exit(status.code().unwrap_or(1));
}
