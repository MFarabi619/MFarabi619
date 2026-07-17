use crate::link::LinkId;

pub const BASE_LINK: &str = LinkId::BaseLink.link_name();
pub const ODOM: &str = "odom";
pub const CHASSIS: &str = LinkId::Chassis.link_name();
pub const CAMERA_LINK: &str = LinkId::CameraLink.link_name();
pub const CAMERA_OPTICAL: &str = LinkId::CameraOptical.link_name();
pub const GPS_LINK: &str = LinkId::GpsLink.link_name();
