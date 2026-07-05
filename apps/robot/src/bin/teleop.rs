use std::time::Duration;

use crossterm::{
    event::{self, Event, KeyCode},
    terminal::{disable_raw_mode, enable_raw_mode},
};
use oxidros::{msg::common_interfaces::geometry_msgs::msg::Twist, prelude::*};

const LINEAR_SPEED_MPS: f64 = 0.5;
const ANGULAR_SPEED_RAD_S: f64 = 1.0;

fn twist(linear: f64, angular: f64) -> Twist {
    let mut msg = Twist::new().unwrap();
    msg.linear.x = linear;
    msg.angular.z = angular;
    msg
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    init_ros_logging("teleop");
    let ctx = Context::new()?;
    let node = ctx.create_node("teleop", None)?;
    let publisher = node.create_publisher::<Twist>("cmd_vel", None)?;

    tracing::info!("w/s drive, a/d turn, space stop, q quit");
    enable_raw_mode()?;

    let outcome = (|| -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut linear = 0.0;
        let mut angular = 0.0;
        loop {
            if event::poll(Duration::from_millis(100))? {
                if let Event::Key(key) = event::read()? {
                    match key.code {
                        KeyCode::Char('w') => linear = LINEAR_SPEED_MPS,
                        KeyCode::Char('s') => linear = -LINEAR_SPEED_MPS,
                        KeyCode::Char('a') => angular = ANGULAR_SPEED_RAD_S,
                        KeyCode::Char('d') => angular = -ANGULAR_SPEED_RAD_S,
                        KeyCode::Char(' ') => {
                            linear = 0.0;
                            angular = 0.0;
                        }
                        KeyCode::Char('q') => return Ok(()),
                        _ => {}
                    }
                }
            }
            publisher.send(&twist(linear, angular))?;
        }
    })();

    let _ = publisher.send(&twist(0.0, 0.0));
    disable_raw_mode()?;
    outcome
}
