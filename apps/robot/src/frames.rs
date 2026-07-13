use description::link::LinkId;

pub const BASE_LINK: &str = LinkId::BaseLink.urdf_name();
pub const ODOM: &str = "odom";
pub const CHASSIS: &str = LinkId::Chassis.urdf_name();
pub const CAMERA_LINK: &str = LinkId::CameraLink.urdf_name();
pub const CAMERA_OPTICAL: &str = LinkId::CameraOptical.urdf_name();
