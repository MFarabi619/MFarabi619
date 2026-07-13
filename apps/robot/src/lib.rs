pub mod bridge;
pub mod camera;
pub mod clock;
pub mod config;
pub mod diagnostics;
pub mod driver;
pub mod frames;
pub mod gps;
pub mod hardware;
pub mod kinematics;
pub mod odometry;
#[cfg(feature = "perception")]
pub mod perception;
#[cfg(feature = "pixi")]
pub mod pixi;
pub mod qos;
#[cfg(feature = "simulator")]
pub mod renderer;
pub mod robot_state_publisher;
pub mod rosout;
pub mod ruckig_profile;
#[cfg(feature = "simulator")]
pub mod simulator;
pub mod webcam;

use std::sync::Arc;

pub use bridge::run_bridge;
pub use camera::{camera_intrinsics, run_camera, CameraProfile};
pub use clock::now_stamp;
pub use config::{BRIDGE_PORT, CAMERA_PORT};
pub use diagnostics::battery_diagnostic_level;
pub use driver::{command_is_stale, run_driver, Config};
pub use gps::{enu_to_geodetic, run_gps};
pub use odometry::integrate_pose;
use oxidros::prelude::*;
#[cfg(feature = "perception")]
pub use perception::{run_gesture_pet, run_green_approach, run_line_follower, LineColor};
#[cfg(feature = "simulator")]
pub use renderer::{CameraRenderer, Scene};
pub use robot_state_publisher::spawn_robot_description;
pub use rosout::{init_logging, init_rosout_logging};
#[cfg(feature = "simulator")]
pub use simulator::run_simulator;

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
    spawn_logged("gps", run_gps(gps_node));
    spawn_bridge(context)?;
    Ok(())
}

pub fn rover_chip(
) -> Result<&'static hardware::gpio::Chip<'static>, Box<dyn std::error::Error + Send + Sync>> {
    let connection: &'static hardware::gpio::Connection = Box::leak(Box::new(
        hardware::gpio::Connection::connect(config::HOST, config::RGPIOD_PORT)?,
    ));
    Ok(Box::leak(Box::new(
        connection.open_chip(config::GPIO_CHIP)?,
    )))
}

pub fn spawn_rover_driver(
    context: &Arc<Context>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let drivetrain = hardware::motor::drivetrain(rover_chip()?)?;
    spawn_sensors(context)?;
    spawn_robot_description(context)?;
    let driver_node = context.create_node("base_controller", None)?;
    spawn_logged(
        "driver",
        run_driver(driver_node, drivetrain, config::rover_config()),
    );
    Ok(())
}
