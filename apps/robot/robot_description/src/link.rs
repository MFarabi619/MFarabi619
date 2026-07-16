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
            LinkId::MountFrontLeft => "front_left_mount_link",
            LinkId::MountFrontRight => "front_right_mount_link",
            LinkId::MountRearLeft => "rear_left_mount_link",
            LinkId::MountRearRight => "rear_right_mount_link",
            LinkId::MotorFrontLeft => "front_left_motor_link",
            LinkId::MotorFrontRight => "front_right_motor_link",
            LinkId::MotorRearLeft => "rear_left_motor_link",
            LinkId::MotorRearRight => "rear_right_motor_link",
            LinkId::WheelFrontLeft => "front_left_wheel_link",
            LinkId::WheelFrontRight => "front_right_wheel_link",
            LinkId::WheelRearLeft => "rear_left_wheel_link",
            LinkId::WheelRearRight => "rear_right_wheel_link",
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
