use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
    time::Duration,
};

use foxglove::{
    messages::{FrameTransform, FrameTransforms, Quaternion, Timestamp, Vector3},
    websocket::{Capability, Client, ClientChannel, ServerListener},
};
use oxidros::{
    core::{TypeDescription, TypeSupport},
    msg::common_interfaces::{
        diagnostic_msgs::msg::DiagnosticArray,
        geometry_msgs::msg::{Pose, Twist},
        nav_msgs::msg::Odometry,
        sensor_msgs::msg::{BatteryState, CameraInfo, Image, NavSatFix},
        std_msgs::msg::String as StringMsg,
    },
    prelude::*,
};

use crate::frames::{BASE_LINK, CAMERA_LINK, CAMERA_OPTICAL, CHASSIS, ODOM};

struct Meshes(HashMap<String, Vec<u8>>);

impl foxglove::websocket::AssetHandler for Meshes {
    fn fetch(&self, uri: String, responder: foxglove::websocket::AssetResponder) {
        match self.0.get(&uri) {
            Some(bytes) => responder.respond_ok(bytes),
            None => responder.respond_err(format!("no asset {uri}")),
        }
    }
}

fn meshes() -> HashMap<String, Vec<u8>> {
    [
        (
            "chassis_aluminum",
            include_bytes!("../meshes/chassis_aluminum.stl").as_slice(),
        ),
        (
            "chassis_bracket",
            include_bytes!("../meshes/chassis_bracket.stl").as_slice(),
        ),
        (
            "chassis_brass",
            include_bytes!("../meshes/chassis_brass.stl").as_slice(),
        ),
        (
            "chassis_motor",
            include_bytes!("../meshes/chassis_motor.stl").as_slice(),
        ),
        (
            "chassis_pcb",
            include_bytes!("../meshes/chassis_pcb.stl").as_slice(),
        ),
        (
            "chassis_plastic",
            include_bytes!("../meshes/chassis_plastic.stl").as_slice(),
        ),
        (
            "chassis_plywood",
            include_bytes!("../meshes/chassis_plywood.stl").as_slice(),
        ),
        (
            "chassis_steel",
            include_bytes!("../meshes/chassis_steel.stl").as_slice(),
        ),
        (
            "wheel_hub",
            include_bytes!("../meshes/wheel_hub.stl").as_slice(),
        ),
        (
            "wheel_rim",
            include_bytes!("../meshes/wheel_rim.stl").as_slice(),
        ),
        (
            "wheel_tire",
            include_bytes!("../meshes/wheel_tire.stl").as_slice(),
        ),
    ]
    .iter()
    .map(|(name, bytes)| (format!("package://robot/meshes/{name}.stl"), bytes.to_vec()))
    .collect()
}

const IDENTITY: (f64, f64, f64, f64) = (0.0, 0.0, 0.0, 1.0);
// camera_link -> camera_optical_frame: rpy(-pi/2, 0, -pi/2) as a quaternion (mirrors urdf/robot.urdf).
const OPTICAL_FRAME_ROTATION: (f64, f64, f64, f64) = (-0.5, 0.5, -0.5, 0.5);
const HALF_TRACK: f64 = 0.527;
const HALF_WHEELBASE: f64 = 0.53;
const WHEEL_AXLE_HEIGHT: f64 = 0.178;
const CAMERA_MOUNT_FORWARD: f64 = 0.15;
const CAMERA_MOUNT_HEIGHT: f64 = 0.2;

fn quaternion_about_y(angle: f64) -> (f64, f64, f64, f64) {
    (0.0, (angle / 2.0).sin(), 0.0, (angle / 2.0).cos())
}

fn transform(
    timestamp: &Timestamp,
    parent: &str,
    child: &str,
    translation: (f64, f64, f64),
    rotation: (f64, f64, f64, f64),
) -> FrameTransform {
    FrameTransform {
        timestamp: Some(*timestamp),
        parent_frame_id: parent.to_string(),
        child_frame_id: child.to_string(),
        translation: Some(Vector3 {
            x: translation.0,
            y: translation.1,
            z: translation.2,
        }),
        rotation: Some(Quaternion {
            x: rotation.0,
            y: rotation.1,
            z: rotation.2,
            w: rotation.3,
        }),
    }
}

fn frame_tree(
    now: &Timestamp,
    pose: &Pose,
    left_angle: f64,
    right_angle: f64,
) -> Vec<FrameTransform> {
    let base_orientation = (
        pose.orientation.x,
        pose.orientation.y,
        pose.orientation.z,
        pose.orientation.w,
    );
    let mut transforms = vec![
        transform(
            now,
            ODOM,
            BASE_LINK,
            (pose.position.x, pose.position.y, 0.0),
            base_orientation,
        ),
        transform(now, BASE_LINK, CHASSIS, (0.0, 0.0, 0.0), IDENTITY),
        transform(
            now,
            BASE_LINK,
            CAMERA_LINK,
            (CAMERA_MOUNT_FORWARD, 0.0, CAMERA_MOUNT_HEIGHT),
            IDENTITY,
        ),
        transform(
            now,
            CAMERA_LINK,
            CAMERA_OPTICAL,
            (0.0, 0.0, 0.0),
            OPTICAL_FRAME_ROTATION,
        ),
    ];
    for (child, forward_sign, left_sign, angle) in [
        ("wheel_fl", 1.0, 1.0, left_angle),
        ("wheel_fr", 1.0, -1.0, right_angle),
        ("wheel_rl", -1.0, 1.0, left_angle),
        ("wheel_rr", -1.0, -1.0, right_angle),
    ] {
        transforms.push(transform(
            now,
            CHASSIS,
            child,
            (
                forward_sign * HALF_WHEELBASE,
                left_sign * HALF_TRACK,
                WHEEL_AXLE_HEIGHT,
            ),
            quaternion_about_y(angle),
        ));
    }
    transforms
}

struct CmdVelRelay {
    tx: tokio::sync::mpsc::UnboundedSender<(String, Vec<u8>)>,
}

impl ServerListener for CmdVelRelay {
    fn on_message_data(&self, _client: Client, channel: &ClientChannel, payload: &[u8]) {
        if channel.topic.contains("cmd_vel") {
            let _ = self.tx.send((channel.encoding.clone(), payload.to_vec()));
        }
    }
}

fn json_field(value: &serde_json::Value, group: &str, axis: &str) -> f64 {
    value
        .get(group)
        .and_then(|g| g.get(axis))
        .and_then(|a| a.as_f64())
        .unwrap_or(0.0)
}

fn decode_twist(encoding: &str, payload: &[u8]) -> Option<Twist> {
    match encoding {
        "cdr" => <Twist as TypeSupport>::from_bytes(payload).ok(),
        "json" => {
            let value: serde_json::Value = serde_json::from_slice(payload).ok()?;
            let mut twist = Twist::new()?;
            twist.linear.x = json_field(&value, "linear", "x");
            twist.linear.y = json_field(&value, "linear", "y");
            twist.linear.z = json_field(&value, "linear", "z");
            twist.angular.x = json_field(&value, "angular", "x");
            twist.angular.y = json_field(&value, "angular", "y");
            twist.angular.z = json_field(&value, "angular", "z");
            Some(twist)
        }
        _ => None,
    }
}

fn dds_to_ros(dds_name: &str) -> String {
    let parts: Vec<&str> = dds_name.split("::").collect();
    if parts.len() >= 4 && parts[2] == "dds_" {
        let type_name = parts[3].strip_suffix('_').unwrap_or(parts[3]);
        format!("{}/{}/{}", parts[0], parts[1], type_name)
    } else {
        dds_name.to_string()
    }
}

fn rewrite_schema_headers(schema: String) -> String {
    schema
        .split_inclusive('\n')
        .map(|line| match line.strip_prefix("MSG: ") {
            Some(rest) => {
                let mut segments = rest.splitn(3, '/');
                match (segments.next(), segments.next(), segments.next()) {
                    (Some(pkg), Some("msg"), Some(tail)) => format!("MSG: {pkg}/{tail}"),
                    _ => line.to_string(),
                }
            }
            None => line.to_string(),
        })
        .collect()
}

fn schema_for(ros_type: &str) -> Option<String> {
    let desc = match ros_type {
        "sensor_msgs/msg/Image" => Image::type_description(),
        "sensor_msgs/msg/CameraInfo" => CameraInfo::type_description(),
        "sensor_msgs/msg/NavSatFix" => NavSatFix::type_description(),
        "sensor_msgs/msg/BatteryState" => BatteryState::type_description(),
        "diagnostic_msgs/msg/DiagnosticArray" => DiagnosticArray::type_description(),
        "geometry_msgs/msg/Twist" => Twist::type_description(),
        "std_msgs/msg/String" => StringMsg::type_description(),
        _ => return None,
    };
    Some(rewrite_schema_headers(desc.to_msg_definition()))
}

pub async fn run_bridge(
    node: Arc<Node>,
    port: u16,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let ctx = node.context().clone();

    let (teleop_tx, mut teleop_rx) = tokio::sync::mpsc::unbounded_channel::<(String, Vec<u8>)>();
    let server = foxglove::WebSocketServer::new()
        .name("bridge")
        .bind("127.0.0.1", port)
        .capabilities([Capability::ClientPublish])
        .supported_encodings(["json", "cdr"])
        .listener(Arc::new(CmdVelRelay { tx: teleop_tx }))
        .fetch_asset_handler(Arc::new(Meshes(meshes())))
        .start()
        .await?;
    tracing::info!("bridge live: ws://127.0.0.1:{port} (connect Lichtblick here)");

    let cmd_vel_pub = node.create_publisher::<Twist>("cmd_vel", None)?;
    tokio::spawn(async move {
        while let Some((encoding, payload)) = teleop_rx.recv().await {
            if let Some(twist) = decode_twist(&encoding, &payload) {
                let _ = cmd_vel_pub.send(&twist);
            }
        }
    });

    let mut odom_sub = node.create_subscriber::<Odometry>("odom", None)?;
    let tf_channel = foxglove::ChannelBuilder::new("/tf").build::<FrameTransforms>();
    tokio::spawn(async move {
        const DT: f64 = 1.0 / 30.0;
        const WHEEL_RADIUS: f64 = 0.178;
        let mut left_angle = 0.0_f64;
        let mut right_angle = 0.0_f64;
        while let Ok(message) = odom_sub.recv().await {
            let odom = &message.sample;
            let linear = odom.twist.twist.linear.x;
            let angular = odom.twist.twist.angular.z;
            left_angle -= (linear - angular * HALF_TRACK) / WHEEL_RADIUS * DT;
            right_angle -= (linear + angular * HALF_TRACK) / WHEEL_RADIUS * DT;
            let now = Timestamp::now();
            let transforms = frame_tree(&now, &odom.pose.pose, left_angle, right_angle);
            tf_channel.log(&FrameTransforms { transforms });
        }
    });

    let mut subscribed: HashSet<String> = HashSet::new();
    let mut poll = tokio::time::interval(Duration::from_secs(1));

    let ctrl_c = tokio::signal::ctrl_c();
    tokio::pin!(ctrl_c);
    loop {
        tokio::select! {
            _ = &mut ctrl_c => break,
            _ = poll.tick() => {
                let graph = ctx.graph_cache();
                for (topic, _ty) in graph.get_topic_names_and_types() {
                    if subscribed.contains(&topic) {
                        continue;
                    }
                    let Some(entity) = graph.get_publishers_info(&topic).into_iter().next() else {
                        continue;
                    };
                    let (Some(dds_type), Some(type_hash)) =
                        (entity.type_name.clone(), entity.type_hash.clone())
                    else {
                        continue;
                    };
                    let ros_type = dds_to_ros(&dds_type);
                    let Some(schema_text) = schema_for(&ros_type) else {
                        continue;
                    };

                    let channel = foxglove::ChannelBuilder::new(&topic)
                        .message_encoding("cdr")
                        .schema(foxglove::Schema::new(&ros_type, "ros2msg", schema_text.into_bytes()))
                        .build_raw()?;

                    let topic_key = topic.strip_prefix('/').unwrap_or(&topic);
                    let key_expr =
                        format!("{}/{}/{}/{}", ctx.domain_id(), topic_key, dds_type, type_hash);
                    let sub = ctx.session().declare_subscriber(&key_expr).await?;
                    tokio::spawn(async move {
                        while let Ok(sample) = sub.recv_async().await {
                            let bytes = sample.payload().to_bytes();
                            channel.log(bytes.as_ref());
                        }
                    });
                    tracing::info!("bridging {topic} [{ros_type}]");
                    subscribed.insert(topic);
                }
            }
        }
    }

    tracing::info!("shutting down");
    server.stop().wait().await;
    Ok(())
}
