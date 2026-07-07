use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use foxglove::{
    messages::{FrameTransform, FrameTransforms, Quaternion, Timestamp, Vector3},
    websocket::{Capability, ChannelView, Client, ClientChannel, ConnectionGraph, ServerListener},
    ChannelId, RawChannel,
};
use oxidros::{
    core::{TypeDescription, TypeSupport},
    msg::{
        common_interfaces::{
            diagnostic_msgs::msg::DiagnosticArray,
            geometry_msgs::msg::{Pose, Twist},
            nav_msgs::msg::Odometry,
            sensor_msgs::msg::{BatteryState, CameraInfo, CompressedImage, Image, NavSatFix},
            std_msgs::msg::String as StringMsg,
        },
        interfaces::rcl_interfaces::msg::Log,
    },
    prelude::*,
};
use zenoh::{
    handlers::RingChannel,
    key_expr::format::{kedefine, keformat},
};
use zenoh_ext::AdvancedSubscriberBuilderExt;

use crate::{
    frames::{BASE_LINK, CHASSIS, ODOM},
    kinematics::{wheel_angular_velocities, WheelSide, WHEELS},
};

kedefine!(pub(crate) topic_keyexpr: "${domain:*}/${topic:**}/${dds_type:*}/${hash:*}");

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

const RING_CHANNEL_CAPACITY: usize = 16;
const BIND_ADDRESS: &str = "127.0.0.1";
const GRAPH_POLL_INTERVAL: Duration = Duration::from_secs(1);

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

fn base_link_transform(now: &Timestamp, pose: &Pose) -> FrameTransform {
    transform(
        now,
        ODOM,
        BASE_LINK,
        (pose.position.x, pose.position.y, 0.0),
        (
            pose.orientation.x,
            pose.orientation.y,
            pose.orientation.z,
            pose.orientation.w,
        ),
    )
}

struct WheelOdometry {
    left_angle: f64,
    right_angle: f64,
    last_update: Instant,
}

impl WheelOdometry {
    fn new() -> Self {
        Self {
            left_angle: 0.0,
            right_angle: 0.0,
            last_update: Instant::now(),
        }
    }

    fn integrate(&mut self, linear: f64, angular: f64) {
        let dt = self.last_update.elapsed().as_secs_f64();
        self.last_update = Instant::now();
        let (left_speed, right_speed) = wheel_angular_velocities(linear, angular);
        self.left_angle += left_speed * dt;
        self.right_angle += right_speed * dt;
    }

    fn angle(&self, side: WheelSide) -> f64 {
        match side {
            WheelSide::Left => self.left_angle,
            WheelSide::Right => self.right_angle,
        }
    }

    fn wheel_transforms(&self, now: &Timestamp) -> Vec<FrameTransform> {
        WHEELS
            .iter()
            .map(|wheel| {
                let (sin, cos) = (self.angle(wheel.side) / 2.0).sin_cos();
                transform(
                    now,
                    CHASSIS,
                    wheel.link(),
                    (wheel.mount[0], wheel.mount[1], wheel.mount[2]),
                    (0.0, sin, 0.0, cos),
                )
            })
            .collect()
    }
}

type LastValues = Arc<Mutex<HashMap<ChannelId, (Arc<RawChannel>, Vec<u8>)>>>;

struct BridgeListener {
    teleop_tx: tokio::sync::mpsc::UnboundedSender<(String, Vec<u8>)>,
    last_values: LastValues,
}

impl ServerListener for BridgeListener {
    fn on_message_data(&self, _client: Client, channel: &ClientChannel, payload: &[u8]) {
        if channel.topic.contains("cmd_vel") {
            let _ = self
                .teleop_tx
                .send((channel.encoding.clone(), payload.to_vec()));
        }
    }

    fn on_subscribe(&self, client: Client, channel: ChannelView) {
        if let Some((raw, last)) = self.last_values.lock().unwrap().get(&channel.id()) {
            if !last.is_empty() {
                raw.log_to_sink(last.as_slice(), client.sink_id());
            }
        }
    }
}

fn decode_twist(encoding: &str, payload: &[u8]) -> Option<Twist> {
    match encoding {
        "cdr" => <Twist as TypeSupport>::from_bytes(payload).ok(),
        "json" => serde_json::from_slice::<Twist>(payload).ok(),
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
                    (Some(package), Some("msg"), Some(tail)) => format!("MSG: {package}/{tail}"),
                    _ => line.to_string(),
                }
            }
            None => line.to_string(),
        })
        .collect()
}

fn schema_for(ros_type: &str) -> Option<String> {
    let description = match ros_type {
        "sensor_msgs/msg/Image" => Image::type_description(),
        "sensor_msgs/msg/CompressedImage" => CompressedImage::type_description(),
        "sensor_msgs/msg/CameraInfo" => CameraInfo::type_description(),
        "sensor_msgs/msg/NavSatFix" => NavSatFix::type_description(),
        "sensor_msgs/msg/BatteryState" => BatteryState::type_description(),
        "diagnostic_msgs/msg/DiagnosticArray" => DiagnosticArray::type_description(),
        "geometry_msgs/msg/Twist" => Twist::type_description(),
        "std_msgs/msg/String" => StringMsg::type_description(),
        "rcl_interfaces/msg/Log" => Log::type_description(),
        _ => return None,
    };
    Some(rewrite_schema_headers(description.to_msg_definition()))
}

pub async fn run_bridge(
    node: Arc<Node>,
    port: u16,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let context = node.context().clone();

    let (teleop_tx, mut teleop_rx) = tokio::sync::mpsc::unbounded_channel::<(String, Vec<u8>)>();
    let last_values: LastValues = Arc::new(Mutex::new(HashMap::new()));
    let server = foxglove::WebSocketServer::new()
        .name("bridge")
        .bind(BIND_ADDRESS, port)
        .capabilities([Capability::ClientPublish, Capability::ConnectionGraph])
        .supported_encodings(["json", "cdr"])
        .listener(Arc::new(BridgeListener {
            teleop_tx,
            last_values: last_values.clone(),
        }))
        .fetch_asset_handler_blocking_fn({
            let meshes = meshes();
            move |_client, uri| {
                meshes
                    .get(&uri)
                    .cloned()
                    .ok_or_else(|| format!("no asset {uri}"))
            }
        })
        .start()
        .await?;
    tracing::info!("bridge live: ws://{BIND_ADDRESS}:{port} (connect Lichtblick here)");

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
        let mut wheels = WheelOdometry::new();
        while let Ok(message) = odom_sub.recv().await {
            let now = Timestamp::now();
            let odom = &message.sample;
            wheels.integrate(odom.twist.twist.linear.x, odom.twist.twist.angular.z);
            let mut transforms = vec![base_link_transform(&now, &odom.pose.pose)];
            transforms.extend(wheels.wheel_transforms(&now));
            tf_channel.log(&FrameTransforms { transforms });
        }
    });

    let mut subscribed_topics: HashSet<String> = HashSet::new();
    let mut poll_interval = tokio::time::interval(GRAPH_POLL_INTERVAL);

    let ctrl_c = tokio::signal::ctrl_c();
    tokio::pin!(ctrl_c);
    loop {
        tokio::select! {
            _ = &mut ctrl_c => break,
            _ = poll_interval.tick() => {
                let graph = context.graph_cache();

                let qualify = |namespace: &str, node: &str| format!("{namespace}/{node}");
                let mut connection_graph = ConnectionGraph::new();
                for (topic, _ty) in graph.get_topic_names_and_types() {
                    let publishers: Vec<String> = graph
                        .get_publishers_info(&topic)
                        .into_iter()
                        .map(|publisher_info| {
                            qualify(&publisher_info.namespace, &publisher_info.node_name)
                        })
                        .collect();
                    if !publishers.is_empty() {
                        connection_graph.set_published_topic(topic.clone(), publishers);
                    }
                    let mut subscribers: Vec<String> = graph
                        .get_subscribers_info(&topic)
                        .into_iter()
                        .map(|subscriber_info| {
                            qualify(&subscriber_info.namespace, &subscriber_info.node_name)
                        })
                        .collect();
                    if subscribed_topics.contains(&topic) {
                        subscribers.push("/bridge".to_string());
                    }
                    if !subscribers.is_empty() {
                        connection_graph.set_subscribed_topic(topic.clone(), subscribers);
                    }
                }
                let _ = server.publish_connection_graph(connection_graph);

                for (topic, _ty) in graph.get_topic_names_and_types() {
                    if subscribed_topics.contains(&topic) {
                        continue;
                    }
                    let Some(publisher_info) = graph.get_publishers_info(&topic).into_iter().next()
                    else {
                        continue;
                    };
                    let (Some(dds_type), Some(type_hash)) =
                        (publisher_info.type_name.clone(), publisher_info.type_hash.clone())
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
                    let channel_id = channel.id();
                    last_values
                        .lock()
                        .unwrap()
                        .insert(channel_id, (channel.clone(), Vec::new()));

                    let topic_key = topic.strip_prefix('/').unwrap_or(&topic);
                    let key_expr = keformat!(
                        topic_keyexpr::formatter(),
                        domain = context.domain_id(),
                        topic = topic_key,
                        dds_type = &dds_type,
                        hash = &type_hash,
                    )?;
                    let subscriber = context
                        .session()
                        .declare_subscriber(&key_expr)
                        .with(RingChannel::new(RING_CHANNEL_CAPACITY))
                        .history(zenoh_ext::HistoryConfig::default().max_samples(RING_CHANNEL_CAPACITY))
                        .await?;
                    let last_values = last_values.clone();
                    tokio::spawn(async move {
                        while let Ok(sample) = subscriber.recv_async().await {
                            let bytes = sample.payload().to_bytes();
                            channel.log(bytes.as_ref());
                            if let Some(entry) = last_values.lock().unwrap().get_mut(&channel_id) {
                                entry.1.clear();
                                entry.1.extend_from_slice(bytes.as_ref());
                            }
                        }
                    });
                    tracing::info!("bridging {topic} [{ros_type}]");
                    subscribed_topics.insert(topic);
                }
            }
        }
    }

    tracing::info!("shutting down");
    server.stop().wait().await;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn topic_keyexpr_matches_the_hand_built_layout() {
        let built = keformat!(
            topic_keyexpr::formatter(),
            domain = 0,
            topic = "camera/image_raw",
            dds_type = "sensor_msgs::msg::dds_::Image_",
            hash = "RIHS01_abc",
        )
        .unwrap();
        assert_eq!(
            built.as_str(),
            "0/camera/image_raw/sensor_msgs::msg::dds_::Image_/RIHS01_abc"
        );
    }
}
