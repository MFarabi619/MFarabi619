const LISTEN_ADDRESS: &str = "0.0.0.0";
const LISTEN_PORT: u16 = 7447;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let endpoint = format!("tcp/{LISTEN_ADDRESS}:{LISTEN_PORT}");

    let mut config = zenoh::Config::default();
    config.insert_json5("mode", "\"router\"")?;
    config.insert_json5("listen/endpoints", &format!("[\"{endpoint}\"]"))?;

    let _session = zenoh::open(config).await?;
    println!("zenoh router: listening on {endpoint}");

    std::future::pending::<()>().await;
    Ok(())
}
