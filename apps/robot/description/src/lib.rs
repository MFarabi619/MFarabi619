use oxidros::msg::{common_interfaces::geometry_msgs::msg::TwistStamped, msg::RosString};

pub mod datums;
pub mod frames;
pub mod link;
pub mod parameters;
pub mod placement;
pub mod time;
pub mod wiring;

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
