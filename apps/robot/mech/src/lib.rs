use oxidros::msg::{common_interfaces::geometry_msgs::msg::TwistStamped, msg::RosString};

pub mod datums;
pub mod dimensions;
pub mod frames;
pub mod link;
pub mod parameters;
pub mod placement;
pub mod time;

use crate::{frames::BASE_LINK, time::now_stamp};

pub const MM_TO_M: f64 = 0.001;
pub const MM3_TO_M3: f64 = 1e-9;
pub const MM5_TO_M5: f64 = 1e-15;

pub const MESH_URI_PREFIX: &str = "package://robot_description/meshes/";

pub fn stamped_twist(linear: f64, angular: f64) -> TwistStamped {
    let mut message = TwistStamped::new().unwrap();
    let (sec, nanosec) = now_stamp();
    message.header.stamp.sec = sec;
    message.header.stamp.nanosec = nanosec;
    message.header.frame_id = RosString::new(BASE_LINK).unwrap();
    message.twist.linear.x = linear;
    message.twist.angular.z = angular;
    message
}

pub fn camera_intrinsics(width: usize, height: usize, fov_deg: f64) -> (f64, f64, f64, f64) {
    let focal = (width as f64 / 2.0) / (fov_deg.to_radians() / 2.0).tan();
    (focal, focal, width as f64 / 2.0, height as f64 / 2.0)
}

#[cfg(feature = "generator")]
pub mod assembly;
#[cfg(feature = "generator")]
pub mod collada;
#[cfg(feature = "generator")]
pub mod config;
#[cfg(feature = "generator")]
pub mod export;
#[cfg(feature = "generator")]
pub mod gltf;
#[cfg(feature = "generator")]
pub mod mass_properties;
#[cfg(feature = "generator")]
pub mod material;
#[cfg(feature = "generator")]
pub mod urdf;

#[cfg(feature = "generator")]
pub use link::{Joint, JointType, LinkId};

#[cfg(feature = "generator")]
pub struct Link {
    pub id: link::LinkId,
    pub origin_world: cadrum::DVec3,
    pub solids: Vec<cadrum::Solid>,
}

#[cfg(feature = "generator")]
pub fn robot_root() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("mech lives under the robot package")
        .to_path_buf()
}

#[cfg(feature = "generator")]
pub fn cad_asset(name: &str) -> std::path::PathBuf {
    robot_root().join("assets").join("step").join(name)
}

#[cfg(feature = "generator")]
#[macro_export]
macro_rules! time_it {
    ($name:expr, $body:expr) => {{
        let start = ::std::time::Instant::now();
        let result = $body;
        eprintln!(
            "[cad] {:<24} {:>7.2}s",
            $name,
            start.elapsed().as_secs_f64()
        );
        result
    }};
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn camera_intrinsics_center_is_half_the_frame() {
        let (_, _, cx, cy) = camera_intrinsics(640, 400, 70.0);
        assert_eq!(cx, 320.0);
        assert_eq!(cy, 200.0);
    }
}
