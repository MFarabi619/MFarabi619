pub mod bridge;
pub mod camera_mount;
pub mod config;
pub mod driver;
#[cfg(feature = "pixi")]
pub mod pixi;
pub mod robot_state_publisher;
pub mod rosout;

use std::sync::Arc;

pub use bridge::run_bridge;
pub use camera_mount::{rover_camera_mount, run_camera_mount};
pub use robot_sensors::{run_camera, run_gps, CameraProfile};
pub use config::{BRIDGE_PORT, CAMERA_PORT};
pub use driver::{run_driver, Config};
use oxidros::prelude::*;
#[cfg(feature = "perception")]
pub use robot_perception::{
    run_gesture, run_green_approach, run_line_follower, run_row_follower, LineColor,
};
pub use robot_state_publisher::spawn_robot_description;
pub use rosout::{init_logging, init_rosout_logging};

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

pub fn spawn_bridge(
    context: &Arc<Context>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let node = context.create_node("bridge", None)?;
    tracing::info!("bridge on ws://localhost:{BRIDGE_PORT}");
    spawn_logged("bridge", run_bridge(node, BRIDGE_PORT));
    Ok(())
}

pub fn spawn_sensors(
    context: &Arc<Context>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let camera_node = context.create_node("camera", None)?;
    spawn_logged(
        "camera",
        run_camera(
            camera_node,
            format!("{}:{CAMERA_PORT}", config::HOST),
            config::CAMERA,
        ),
    );
    let gps_node = context.create_node("gps", None)?;
    spawn_logged("gps", run_gps(gps_node, config::HOST));
    spawn_bridge(context)?;
    Ok(())
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
    let gesture_node = context.create_node("gesture", None)?;
    spawn_logged("gesture", run_gesture(gesture_node, false));
    Ok(())
}

pub fn rover_chip(
) -> Result<&'static robot_drivers::gpio::Chip<'static>, Box<dyn std::error::Error + Send + Sync>> {
    let connection: &'static robot_drivers::gpio::Connection = Box::leak(Box::new(
        robot_drivers::gpio::Connection::connect(config::HOST, config::RGPIOD_PORT)?,
    ));
    Ok(Box::leak(Box::new(
        connection.open_chip(config::GPIO_CHIP)?,
    )))
}

pub fn spawn_rover_driver(
    context: &Arc<Context>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let drivetrain = robot_drivers::motor::drivetrain(rover_chip()?)?;
    spawn_sensors(context)?;
    spawn_robot_description(context)?;
    let driver_node = context.create_node("base_controller", None)?;
    spawn_logged(
        "driver",
        run_driver(driver_node, drivetrain, config::rover_config()),
    );
    Ok(())
}
