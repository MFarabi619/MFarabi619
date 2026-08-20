use std::{
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};

use oxidros::{
    msg::{common_interfaces::geometry_msgs::msg::TwistStamped, msg::RosString},
    prelude::*,
};

use crate::BoxError;

/// ROS2 wall-clock stamp `(sec, nanosec)`, matching `robot_description::time::now_stamp`.
pub fn now_stamp() -> (i32, u32) {
    let since_epoch = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    (since_epoch.as_secs() as i32, since_epoch.subsec_nanos())
}

/// Publishes `TwistStamped` on a twist_mux input topic. Same oxidros/zenoh path
/// `driver.rs` receives with, so it joins the running rmw_zenoh graph directly.
pub struct CmdVelPublisher {
    publisher: Publisher<TwistStamped>,
    frame_id: String,
}

impl CmdVelPublisher {
    pub fn new(node: &Arc<Node>, topic: &str, frame_id: &str) -> Result<Self, BoxError> {
        Ok(Self {
            publisher: node.create_publisher::<TwistStamped>(topic, None)?,
            frame_id: frame_id.to_owned(),
        })
    }

    pub fn send(&self, linear: f64, angular: f64) -> Result<(), BoxError> {
        let (sec, nanosec) = now_stamp();
        let mut message = TwistStamped::new().unwrap();
        message.header.stamp.sec = sec;
        message.header.stamp.nanosec = nanosec;
        message.header.frame_id = RosString::new(&self.frame_id).unwrap();
        message.twist.linear.x = linear;
        message.twist.angular.z = angular;
        self.publisher.send(&message)?;
        Ok(())
    }
}
