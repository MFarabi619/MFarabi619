use std::time::Duration;

use oxidros::msg::common_interfaces::geometry_msgs::msg::Twist;

pub mod approach;
pub mod gesture;
pub mod line;
pub mod onnx;
pub mod palm;

pub use approach::run_green_approach;
pub use gesture::run_gesture_pet;
pub use line::{run_line_follower, LineColor};

pub(crate) const WATCHDOG_TIMEOUT: Duration = Duration::from_millis(300);

pub(crate) fn twist(linear: f64, angular: f64) -> Twist {
    let mut message = Twist::new().unwrap();
    message.linear.x = linear;
    message.angular.z = angular;
    message
}
