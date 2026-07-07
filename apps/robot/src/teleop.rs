use std::{sync::Arc, time::Duration};

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

pub fn run_teleop(node: Arc<Node>) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let drive = node.create_publisher::<Twist>("cmd_vel", None)?;

    tracing::info!("arrows drive, space stop, q quit");
    enable_raw_mode()?;

    let outcome = (|| -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut linear = 0.0;
        let mut angular = 0.0;
        loop {
            if event::poll(Duration::from_millis(100))? {
                if let Event::Key(key) = event::read()? {
                    match key.code {
                        KeyCode::Up => linear = LINEAR_SPEED_MPS,
                        KeyCode::Down => linear = -LINEAR_SPEED_MPS,
                        KeyCode::Left => angular = ANGULAR_SPEED_RAD_S,
                        KeyCode::Right => angular = -ANGULAR_SPEED_RAD_S,
                        KeyCode::Char(' ') => {
                            linear = 0.0;
                            angular = 0.0;
                        }
                        KeyCode::Char('q') => return Ok(()),
                        _ => {}
                    }
                }
            }
            drive.send(&twist(linear, angular))?;
        }
    })();

    let _ = drive.send(&twist(0.0, 0.0));
    disable_raw_mode()?;
    outcome
}
