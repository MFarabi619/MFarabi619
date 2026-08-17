pub mod config;
pub mod diagnostics;
pub mod driver;
#[allow(
    dead_code,
    unused_imports,
    non_camel_case_types,
    clippy::all,
    clippy::upper_case_acronyms
)]
pub mod platform_msgs {
    include!(concat!(env!("OUT_DIR"), "/generated/mod.rs"));
}
#[cfg(feature = "pixi")]
pub mod pixi;

use std::sync::Arc;

pub use driver::{run_driver, Config};
use oxidros::prelude::*;
#[cfg(feature = "perception")]
pub use robot_perception::{
    run_gesture, run_green_approach, run_line_follower, run_row_follower, LineColor,
};

pub fn spawn_logged(
    task_name: &'static str,
    future: impl std::future::Future<Output = Result<(), Box<dyn std::error::Error + Send + Sync>>>
        + Send
        + 'static,
) {
    tokio::spawn(async move {
        if let Err(error) = future.await {
            tracing::error!("{task_name} stopped: {error}");
        }
    });
}

#[cfg(feature = "pixi")]
pub async fn ensure_router() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    const ROUTER_ENDPOINT: &str = "127.0.0.1:7447";
    if tokio::net::TcpStream::connect(ROUTER_ENDPOINT).await.is_ok() {
        return Ok(());
    }
    tokio::spawn(async {
        let argv = ["ros2", "run", "rmw_zenoh_cpp", "rmw_zenohd"].map(String::from);
        match pixi::run(&argv, &[], None).await {
            Ok(status) => tracing::error!("zenoh router exited: {status}"),
            Err(error) => tracing::error!("zenoh router failed: {error}"),
        }
    });
    for _ in 0..50 {
        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
        if tokio::net::TcpStream::connect(ROUTER_ENDPOINT).await.is_ok() {
            return Ok(());
        }
    }
    Err("zenoh router did not start within 10s".into())
}

#[cfg(feature = "perception")]
pub fn spawn_perception(
    context: &Arc<Context>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let line_node = context.create_node("line_follower", None)?;
    spawn_logged(
        "line_follower",
        run_line_follower(line_node, LineColor::White, false),
    );
    let row_node = context.create_node("row_follower", None)?;
    spawn_logged("row_follower", run_row_follower(row_node, false));
    let gesture_node = context.create_node("gesture_recognizer", None)?;
    spawn_logged("gesture_recognizer", run_gesture(gesture_node, false));
    Ok(())
}

pub fn robot3_chip(
) -> Result<&'static robot_drivers::gpio::Chip<'static>, Box<dyn std::error::Error + Send + Sync>> {
    let connection: &'static robot_drivers::gpio::Connection = Box::leak(Box::new(
        robot_drivers::gpio::Connection::connect(config::RGPIOD_HOST, config::RGPIOD_PORT)?,
    ));
    Ok(Box::leak(Box::new(
        connection.open_chip(config::GPIO_CHIP)?,
    )))
}

pub fn spawn_robot3_driver(
    context: &Arc<Context>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let drivetrain = config::robot3_drivetrain(robot3_chip()?)?;
    let driver_node = context.create_node("base_controller", None)?;
    spawn_logged(
        "driver",
        run_driver(driver_node, drivetrain, config::robot3_config()),
    );
    Ok(())
}
