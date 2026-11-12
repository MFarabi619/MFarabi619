use std::time::Duration;

pub(crate) use robot_description::stamped_twist as twist;

pub mod approach;
pub mod gesture;
pub mod line;
pub mod parameters;
pub mod row;

pub use approach::run_green_approach;
pub use gesture::run_gesture;
pub use line::{run_line_follower, LineColor};
pub use row::run_row_follower;

pub(crate) const WATCHDOG_TIMEOUT: Duration = Duration::from_millis(300);
pub(crate) const LOG_STRIDE_FRAMES: u64 = 15;
