use std::{error::Error, fs, path::Path};

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
    pub gpio_chip: u32,
    pub pwm_frequency_hz: f32,
    pub max_linear_velocity_mps: f64,
    pub left: DrivetrainSide,
    pub right: DrivetrainSide,
}

#[derive(Debug, Default, Deserialize)]
pub struct DrivetrainSide {
    pub pwm_chip: u32,
    pub pwm_channel: u32,
    pub dir_pin: u32,
    pub forward_level: bool,
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
    pub camera: Vec<Sensor>,
    #[serde(default)]
    pub gps: Vec<Sensor>,
    #[serde(default)]
    pub imu: Vec<Sensor>,
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
