use std::sync::Arc;

use oxidros::{
    core::qos::{DurabilityPolicy, HistoryPolicy},
    msg::{common_interfaces::std_msgs::msg::String as StringMsg, msg::RosString},
    prelude::*,
};

const ROBOT_URDF: &str = include_str!("../robot_description/urdf/robot.urdf");

pub fn spawn_robot_description(
    context: &Arc<Context>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let node = context.create_node("robot_state_publisher", None)?;
    let publisher = node
        .create_publisher::<StringMsg>(
            "robot_description",
            Some(Profile {
                durability: DurabilityPolicy::TransientLocal,
                history: HistoryPolicy::KeepLast,
                depth: 1,
                ..Default::default()
            }),
        )?;
    let mut description = StringMsg::new().unwrap();
    description.data = RosString::new(ROBOT_URDF).unwrap();
    publisher.send(&description)?;
    tokio::spawn(async move {
        let _keep_alive = (node, publisher);
        std::future::pending::<()>().await;
    });
    Ok(())
}
