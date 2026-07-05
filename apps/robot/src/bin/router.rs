#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut config = zenoh::Config::default();
    config.insert_json5("mode", "\"router\"")?;
    config.insert_json5("listen/endpoints", "[\"tcp/127.0.0.1:7447\"]")?;

    let _session = zenoh::open(config).await?;
    println!("zenoh router: listening on tcp/127.0.0.1:7447");

    std::future::pending::<()>().await;
    Ok(())
}
