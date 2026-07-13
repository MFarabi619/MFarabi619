use glam::DVec3;

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub enum LinkId {
    BaseLink,
    BaseFootprint,
    Chassis,
    MountFrontLeft,
    MountFrontRight,
    MountRearLeft,
    MountRearRight,
    MotorFrontLeft,
    MotorFrontRight,
    MotorRearLeft,
    MotorRearRight,
    WheelFrontLeft,
    WheelFrontRight,
    WheelRearLeft,
    WheelRearRight,
    CameraLink,
    CameraOptical,
}

impl LinkId {
    pub const fn urdf_name(self) -> &'static str {
        match self {
            LinkId::BaseLink => "base_link",
            LinkId::BaseFootprint => "base_footprint",
            LinkId::Chassis => "chassis",
            LinkId::MountFrontLeft => "mount_fl",
            LinkId::MountFrontRight => "mount_fr",
            LinkId::MountRearLeft => "mount_rl",
            LinkId::MountRearRight => "mount_rr",
            LinkId::MotorFrontLeft => "motor_fl",
            LinkId::MotorFrontRight => "motor_fr",
            LinkId::MotorRearLeft => "motor_rl",
            LinkId::MotorRearRight => "motor_rr",
            LinkId::WheelFrontLeft => "wheel_fl",
            LinkId::WheelFrontRight => "wheel_fr",
            LinkId::WheelRearLeft => "wheel_rl",
            LinkId::WheelRearRight => "wheel_rr",
            LinkId::CameraLink => "camera_link",
            LinkId::CameraOptical => "camera_optical_frame",
        }
    }
}

pub struct Joint {
    pub name: &'static str,
    pub parent: LinkId,
    pub child: LinkId,
    pub joint_type: JointType,
    pub axis: Option<DVec3>,
    pub rpy: Option<[f64; 3]>,
}

pub enum JointType {
    Fixed,
    Continuous,
}
