use std::{sync::Arc, time::Instant};

use robot_description::{
    frames::{BASE_LINK, ODOM},
    placement::Side,
};
use oxidros::{
    msg::{
        common_interfaces::{nav_msgs::msg::Odometry as OdometryMsg, sensor_msgs::msg::JointState},
        msg::{RosString, RosStringSeq},
    },
    prelude::*,
};

use robot_description::time::now_stamp;

use crate::kinematics::{wheel_angular_velocities, DRIVE_WHEELS};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

pub struct Odometry {
    joint_states: Publisher<JointState>,
    odom: Publisher<OdometryMsg>,
    x: f64,
    y: f64,
    heading_radians: f64,
    linear_meters_per_second: f64,
    angular_radians_per_second: f64,
    left_wheel_angle_radians: f64,
    right_wheel_angle_radians: f64,
    last_update: Instant,
}

impl Odometry {
    pub fn new(node: &Arc<Node>) -> Result<Self, BoxError> {
        Ok(Self {
            joint_states: node.create_publisher::<JointState>("joint_states", None)?,
            odom: node.create_publisher::<OdometryMsg>("odom", None)?,
            x: 0.0,
            y: 0.0,
            heading_radians: 0.0,
            linear_meters_per_second: 0.0,
            angular_radians_per_second: 0.0,
            left_wheel_angle_radians: 0.0,
            right_wheel_angle_radians: 0.0,
            last_update: Instant::now(),
        })
    }

    pub fn set_velocity_command(
        &mut self,
        linear_meters_per_second: f64,
        angular_radians_per_second: f64,
    ) {
        self.linear_meters_per_second = linear_meters_per_second;
        self.angular_radians_per_second = angular_radians_per_second;
    }

    pub fn stop(&mut self) {
        self.linear_meters_per_second = 0.0;
        self.angular_radians_per_second = 0.0;
    }

    pub fn publish(&mut self) -> Result<(), BoxError> {
        let delta_seconds = self.last_update.elapsed().as_secs_f64();
        self.last_update = Instant::now();
        (self.x, self.y, self.heading_radians) = integrate_pose(
            self.x,
            self.y,
            self.heading_radians,
            self.linear_meters_per_second,
            self.angular_radians_per_second,
            delta_seconds,
        );
        let (left_velocity, right_velocity) = wheel_angular_velocities(
            self.linear_meters_per_second,
            self.angular_radians_per_second,
        );
        self.left_wheel_angle_radians += left_velocity * delta_seconds;
        self.right_wheel_angle_radians += right_velocity * delta_seconds;

        self.joint_states.send(&self.joint_state())?;
        self.odom.send(&self.odom_message())?;
        Ok(())
    }

    fn joint_state(&self) -> JointState {
        joint_state_message(self.left_wheel_angle_radians, self.right_wheel_angle_radians)
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
        let (z, w) = (self.heading_radians / 2.0).sin_cos();
        message.pose.pose.orientation.z = z;
        message.pose.pose.orientation.w = w;
        message.twist.twist.linear.x = self.linear_meters_per_second;
        message.twist.twist.angular.z = self.angular_radians_per_second;
        message
    }
}

pub fn joint_state_message(
    left_wheel_angle_radians: f64,
    right_wheel_angle_radians: f64,
) -> JointState {
    let (sec, nanosec) = now_stamp();
    let mut message = JointState::new().unwrap();
    message.header.stamp.sec = sec;
    message.header.stamp.nanosec = nanosec;

    let mut names = RosStringSeq::<0, 0>::new(DRIVE_WHEELS.len()).unwrap();
    for (slot, wheel) in names.as_mut_slice().iter_mut().zip(DRIVE_WHEELS.iter()) {
        slot.assign(wheel.joint_name);
    }
    message.name = names;

    let positions: Vec<f64> = DRIVE_WHEELS
        .iter()
        .map(|wheel| match wheel.corner.side() {
            Side::Left => left_wheel_angle_radians,
            Side::Right => right_wheel_angle_radians,
        })
        .collect();
    message.position = positions.as_slice().try_into().unwrap();
    message
}

pub fn integrate_pose(
    x: f64,
    y: f64,
    heading_radians: f64,
    linear_meters_per_second: f64,
    angular_radians_per_second: f64,
    delta_seconds: f64,
) -> (f64, f64, f64) {
    let heading_radians = heading_radians + angular_radians_per_second * delta_seconds;
    let x = x + linear_meters_per_second * heading_radians.cos() * delta_seconds;
    let y = y + linear_meters_per_second * heading_radians.sin() * delta_seconds;
    (x, y, heading_radians)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn driving_straight_moves_along_x() {
        let (x, y, heading_radians) = integrate_pose(0.0, 0.0, 0.0, 1.0, 0.0, 1.0);
        assert!(x > 0.0);
        assert_eq!(y, 0.0);
        assert_eq!(heading_radians, 0.0);
    }

    #[test]
    fn turning_changes_heading() {
        let (_, _, heading_radians) = integrate_pose(0.0, 0.0, 0.0, 0.0, 1.0, 0.5);
        assert!(heading_radians > 0.0);
    }

    #[test]
    fn resting_stays_put() {
        let resting = integrate_pose(2.0, 3.0, 1.0, 0.0, 0.0, 1.0);
        assert_eq!(resting, (2.0, 3.0, 1.0));
    }
}
