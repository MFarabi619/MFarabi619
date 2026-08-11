use std::{collections::HashMap, error::Error, fs, path::Path};

use serde::Deserialize;

#[derive(Debug, Default, Deserialize)]
pub struct RobotConfig {
    #[serde(default)]
    pub system: System,
    #[serde(default)]
    pub platform: Platform,
    #[serde(default)]
    pub sensors: Sensors,
    #[serde(default)]
    pub mounts: Mounts,
}

#[derive(Debug, Default, Deserialize)]
pub struct Platform {
    #[serde(default)]
    pub drivetrain: Drivetrain,
}

#[derive(Debug, Default, Deserialize)]
pub struct Drivetrain {
    #[serde(default)]
    pub pwm_frequency_hz: f32,
    pub max_linear_velocity_mps: f64,
    pub left: DrivetrainSide,
    pub right: DrivetrainSide,
}

#[derive(Debug, Default, Deserialize)]
pub struct DrivetrainSide {
    #[serde(default)]
    pub pwm_pin: Pin,
    #[serde(default)]
    pub dir_pin: Pin,
    #[serde(default)]
    pub forward_level: bool,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub enum Pin {
    Number(u32),
    Designator(String),
}

impl Default for Pin {
    fn default() -> Self {
        Pin::Number(0)
    }
}

#[derive(Debug, Default, Deserialize)]
pub struct System {
    #[serde(default)]
    pub namespace: String,
    #[serde(default)]
    pub hosts: Vec<Host>,
}

#[derive(Debug, Deserialize)]
pub struct Host {
    pub ip: String,
}

#[derive(Debug, Default, Deserialize)]
pub struct Sensors {
    #[serde(default)]
    pub camera: Vec<CameraSensor>,
    #[serde(default)]
    pub gps: Vec<Sensor>,
    #[serde(default)]
    pub imu: Vec<ImuSensor>,
}

#[derive(Debug, Deserialize)]
pub struct Sensor {
    pub model: String,
    pub parent: String,
    #[serde(default)]
    pub xyz: [f64; 3],
    #[serde(default)]
    pub rpy: [f64; 3],
}

#[derive(Debug, Deserialize)]
pub struct CameraSensor {
    pub model: String,
    #[serde(default = "enabled_by_default")]
    pub launch_enabled: bool,
    pub parent: String,
    #[serde(default)]
    pub xyz: [f64; 3],
    #[serde(default)]
    pub rpy: [f64; 3],
    #[serde(default)]
    pub ros_parameters: HashMap<String, CameraParameters>,
}

#[derive(Debug, Default, Deserialize)]
pub struct CameraParameters {
    pub color_width: Option<u32>,
    pub color_height: Option<u32>,
    pub color_fps: Option<u32>,
    #[serde(default)]
    pub enable_depth: bool,
}

#[derive(Debug, Deserialize)]
pub struct ImuSensor {
    pub model: String,
    pub parent: String,
    #[serde(default)]
    pub xyz: [f64; 3],
    #[serde(default)]
    pub rpy: [f64; 3],
    #[serde(default)]
    pub ros_parameters: HashMap<String, ImuParameters>,
}

#[derive(Debug, Default, Deserialize)]
pub struct ImuParameters {
    pub rate_hz: Option<f64>,
}

fn enabled_by_default() -> bool {
    true
}

#[derive(Debug, Default, Deserialize)]
pub struct Mounts {
    #[serde(default)]
    pub camera_mount: Vec<Placement>,
}

#[derive(Debug, Deserialize)]
pub struct Placement {
    pub parent: String,
    #[serde(default)]
    pub xyz: [f64; 3],
    #[serde(default)]
    pub rpy: [f64; 3],
}

pub fn load(path: &Path) -> Result<RobotConfig, Box<dyn Error>> {
    Ok(serde_yaml::from_str(&fs::read_to_string(path)?)?)
}
