use std::f64::consts::FRAC_PI_2;

use glam::DVec3;

use crate::{
    datums::{
        MOTOR_GEARBOX_BACK_FACE_FROM_STEP_ORIGIN_MM, MOTOR_MOUNT_SHAFT_DROP_FROM_TOP_MM,
        MOTOR_MOUNT_SHAFT_SETBACK_FROM_CENTER_MM, MOTOR_MOUNT_WIDTH_MM,
        WHEEL_HUB_INBOARD_FACE_FROM_STEP_ORIGIN_MM, WHEEL_TREAD_DIAMETER_MM,
    },
    link::{Joint, JointType, LinkId},
    parameters::{
        AXLE_INSET_FROM_FRAME_END_MM, FRAME_LENGTH_MM, FRAME_TOP_Z_MM,
        FRAME_WIDTH_MM, RAIL_CROSS_HEIGHT_MM, RAIL_CROSS_WIDTH_MM,
        WHEEL_HUB_CLEARANCE_FROM_MOTOR_FACE_MM,
    },
};

pub const CAMERA_OPTICAL_RPY: [f64; 3] = [-FRAC_PI_2, 0.0, -FRAC_PI_2];

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub enum Side {
    Left,
    Right,
}

#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub enum Corner {
    RearLeft,
    RearRight,
    FrontLeft,
    FrontRight,
}

impl Corner {
    pub const ALL: [Corner; 4] = [
        Corner::RearLeft,
        Corner::RearRight,
        Corner::FrontLeft,
        Corner::FrontRight,
    ];

    pub const fn side(self) -> Side {
        match self {
            Corner::RearLeft | Corner::FrontLeft => Side::Left,
            Corner::RearRight | Corner::FrontRight => Side::Right,
        }
    }

    pub const fn axle_x(self) -> f64 {
        match self {
            Corner::FrontLeft | Corner::FrontRight => {
                FRAME_LENGTH_MM / 2.0 - AXLE_INSET_FROM_FRAME_END_MM
            }
            Corner::RearLeft | Corner::RearRight => {
                -FRAME_LENGTH_MM / 2.0 + AXLE_INSET_FROM_FRAME_END_MM
            }
        }
    }

    pub const fn mount_link(self) -> LinkId {
        match self {
            Corner::RearLeft => LinkId::MountRearLeft,
            Corner::RearRight => LinkId::MountRearRight,
            Corner::FrontLeft => LinkId::MountFrontLeft,
            Corner::FrontRight => LinkId::MountFrontRight,
        }
    }

    pub const fn motor_link(self) -> LinkId {
        match self {
            Corner::RearLeft => LinkId::MotorRearLeft,
            Corner::RearRight => LinkId::MotorRearRight,
            Corner::FrontLeft => LinkId::MotorFrontLeft,
            Corner::FrontRight => LinkId::MotorFrontRight,
        }
    }

    pub const fn wheel_link(self) -> LinkId {
        match self {
            Corner::RearLeft => LinkId::WheelRearLeft,
            Corner::RearRight => LinkId::WheelRearRight,
            Corner::FrontLeft => LinkId::WheelFrontLeft,
            Corner::FrontRight => LinkId::WheelFrontRight,
        }
    }
}

const fn outboard_sign(side: Side) -> f64 {
    match side {
        Side::Left => 1.0,
        Side::Right => -1.0,
    }
}

pub fn mount_origin(corner: Corner) -> DVec3 {
    let rail_inboard_face_from_centerline = FRAME_WIDTH_MM / 2.0 - RAIL_CROSS_WIDTH_MM;
    let mount_center_from_centerline =
        rail_inboard_face_from_centerline + MOTOR_MOUNT_WIDTH_MM / 2.0;
    let mount_top_z = FRAME_TOP_Z_MM - RAIL_CROSS_HEIGHT_MM;
    DVec3::new(
        corner.axle_x(),
        outboard_sign(corner.side()) * mount_center_from_centerline,
        mount_top_z,
    )
}

pub fn motor_offset_from_mount(side: Side) -> DVec3 {
    DVec3::new(
        -MOTOR_MOUNT_SHAFT_SETBACK_FROM_CENTER_MM,
        outboard_sign(side)
            * (MOTOR_MOUNT_WIDTH_MM / 2.0 + MOTOR_GEARBOX_BACK_FACE_FROM_STEP_ORIGIN_MM),
        -MOTOR_MOUNT_SHAFT_DROP_FROM_TOP_MM,
    )
}

pub fn wheel_offset_from_motor(side: Side) -> DVec3 {
    DVec3::new(
        0.0,
        outboard_sign(side)
            * (WHEEL_HUB_CLEARANCE_FROM_MOTOR_FACE_MM + WHEEL_HUB_INBOARD_FACE_FROM_STEP_ORIGIN_MM),
        0.0,
    )
}

pub fn motor_origin(corner: Corner) -> DVec3 {
    mount_origin(corner) + motor_offset_from_mount(corner.side())
}

pub fn wheel_origin(corner: Corner) -> DVec3 {
    motor_origin(corner) + wheel_offset_from_motor(corner.side())
}

pub fn ground_z() -> f64 {
    wheel_origin(Corner::FrontLeft).z - WHEEL_TREAD_DIAMETER_MM / 2.0
}

pub fn joint_table() -> Vec<Joint> {
    let fixed = |name, parent, child| Joint {
        name,
        parent,
        child,
        joint_type: JointType::Fixed,
        axis: None,
        rpy: None,
    };
    let wheel_continuous = |name, parent, child| Joint {
        name,
        parent,
        child,
        joint_type: JointType::Continuous,
        axis: Some(DVec3::Y),
        rpy: None,
    };
    vec![
        fixed("chassis_joint", LinkId::BaseLink, LinkId::Chassis),
        fixed(
            "base_footprint_joint",
            LinkId::BaseLink,
            LinkId::BaseFootprint,
        ),
        fixed("front_left_mount_joint", LinkId::Chassis, LinkId::MountFrontLeft),
        fixed("front_right_mount_joint", LinkId::Chassis, LinkId::MountFrontRight),
        fixed("rear_left_mount_joint", LinkId::Chassis, LinkId::MountRearLeft),
        fixed("rear_right_mount_joint", LinkId::Chassis, LinkId::MountRearRight),
        fixed(
            "front_left_motor_joint",
            LinkId::MountFrontLeft,
            LinkId::MotorFrontLeft,
        ),
        fixed(
            "front_right_motor_joint",
            LinkId::MountFrontRight,
            LinkId::MotorFrontRight,
        ),
        fixed(
            "rear_left_motor_joint",
            LinkId::MountRearLeft,
            LinkId::MotorRearLeft,
        ),
        fixed(
            "rear_right_motor_joint",
            LinkId::MountRearRight,
            LinkId::MotorRearRight,
        ),
        wheel_continuous(
            "front_left_wheel_joint",
            LinkId::MotorFrontLeft,
            LinkId::WheelFrontLeft,
        ),
        wheel_continuous(
            "front_right_wheel_joint",
            LinkId::MotorFrontRight,
            LinkId::WheelFrontRight,
        ),
        wheel_continuous(
            "rear_left_wheel_joint",
            LinkId::MotorRearLeft,
            LinkId::WheelRearLeft,
        ),
        wheel_continuous(
            "rear_right_wheel_joint",
            LinkId::MotorRearRight,
            LinkId::WheelRearRight,
        ),
    ]
}
