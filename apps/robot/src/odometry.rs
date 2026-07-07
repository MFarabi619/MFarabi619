use std::{sync::Arc, time::Instant};

use oxidros::{
    msg::{
        common_interfaces::{nav_msgs::msg::Odometry as OdometryMsg, sensor_msgs::msg::JointState},
        msg::{RosString, RosStringSeq},
    },
    prelude::*,
};

use crate::{
    frames::{BASE_LINK, ODOM},
    integrate_pose,
    kinematics::{wheel_angular_velocities, WheelSide, WHEELS},
    now_stamp,
};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

pub struct Odometry {
    joint_states: Publisher<JointState>,
    odom: Publisher<OdometryMsg>,
    x: f64,
    y: f64,
    theta: f64,
    linear: f64,
    angular: f64,
    left_wheel_angle: f64,
    right_wheel_angle: f64,
    last_update: Instant,
}

impl Odometry {
    pub fn new(node: &Arc<Node>) -> Result<Self, BoxError> {
        Ok(Self {
            joint_states: node.create_publisher::<JointState>("joint_states", None)?,
            odom: node.create_publisher::<OdometryMsg>("odom", None)?,
            x: 0.0,
            y: 0.0,
            theta: 0.0,
            linear: 0.0,
            angular: 0.0,
            left_wheel_angle: 0.0,
            right_wheel_angle: 0.0,
            last_update: Instant::now(),
        })
    }

    pub fn set_command(&mut self, linear: f64, angular: f64) {
        self.linear = linear;
        self.angular = angular;
    }

    pub fn stop(&mut self) {
        self.linear = 0.0;
        self.angular = 0.0;
    }

    fn wheel_angle(&self, side: WheelSide) -> f64 {
        match side {
            WheelSide::Left => self.left_wheel_angle,
            WheelSide::Right => self.right_wheel_angle,
        }
    }

    pub fn publish(&mut self) -> Result<(), BoxError> {
        let dt = self.last_update.elapsed().as_secs_f64();
        self.last_update = Instant::now();
        (self.x, self.y, self.theta) =
            integrate_pose(self.x, self.y, self.theta, self.linear, self.angular, dt);
        let (left_speed, right_speed) = wheel_angular_velocities(self.linear, self.angular);
        self.left_wheel_angle += left_speed * dt;
        self.right_wheel_angle += right_speed * dt;

        self.joint_states.send(&self.joint_state())?;
        self.odom.send(&self.odom_message())?;
        Ok(())
    }

    fn joint_state(&self) -> JointState {
        let (sec, nanosec) = now_stamp();
        let mut message = JointState::new().unwrap();
        message.header.stamp.sec = sec;
        message.header.stamp.nanosec = nanosec;

        let mut names = RosStringSeq::<0, 0>::new(WHEELS.len()).unwrap();
        for (slot, wheel) in names.as_mut_slice().iter_mut().zip(&WHEELS) {
            slot.assign(wheel.joint);
        }
        message.name = names;

        let positions: Vec<f64> = WHEELS
            .iter()
            .map(|wheel| self.wheel_angle(wheel.side))
            .collect();
        message.position = positions.as_slice().try_into().unwrap();
        message
    }

    fn odom_message(&self) -> OdometryMsg {
        let (sec, nanosec) = now_stamp();
        let mut message = OdometryMsg::new().unwrap();
        message.header.stamp.sec = sec;
        message.header.stamp.nanosec = nanosec;
        message.header.frame_id = RosString::new(ODOM).unwrap();
        message.child_frame_id = RosString::new(BASE_LINK).unwrap();
        message.pose.pose.position.x = self.x;
        message.pose.pose.position.y = self.y;
        message.pose.pose.orientation.z = (self.theta / 2.0).sin();
        message.pose.pose.orientation.w = (self.theta / 2.0).cos();
        message.twist.twist.linear.x = self.linear;
        message.twist.twist.angular.z = self.angular;
        message
    }
}
