use cadrum::{DVec3, Solid};

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub enum LinkId {
    BaseLink,
    Chassis,
    WheelFrontLeft,
    WheelFrontRight,
    WheelRearLeft,
    WheelRearRight,
}

impl LinkId {
    pub const fn urdf_name(self) -> &'static str {
        match self {
            LinkId::BaseLink => "base_link",
            LinkId::Chassis => "chassis",
            LinkId::WheelFrontLeft => "wheel_fl",
            LinkId::WheelFrontRight => "wheel_fr",
            LinkId::WheelRearLeft => "wheel_rl",
            LinkId::WheelRearRight => "wheel_rr",
        }
    }
}

pub struct Link {
    pub id: LinkId,
    pub origin_world: DVec3,
    pub solids: Vec<Solid>,
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
