use std::{
    collections::{HashMap, HashSet},
    fs,
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Duration,
};

use robot_description::{
    frames::{BASE_LINK, ODOM},
    placement::wheel_offset_from_motor,
    stamped_twist, MESH_URI_PREFIX, MM_TO_M,
};
use foxglove::{
    messages::{FrameTransform, FrameTransforms, Quaternion, Timestamp, Vector3},
    websocket::{
        service::{Service, ServiceSchema},
        Capability, ChannelView, Client, ClientChannel, ConnectionGraph, ServerListener,
    },
    ChannelId, RawChannel,
};
use oxidros::{
    core::{TypeDescription, TypeSupport},
    msg::{
        common_interfaces::{
            diagnostic_msgs::msg::DiagnosticArray,
            geometry_msgs::msg::{Pose, Twist, TwistStamped},
            nav_msgs::msg::Odometry,
            sensor_msgs::msg::{
                BatteryState, CameraInfo, CompressedImage, Image, JointState, NavSatFix,
            },
            std_msgs::msg::String as StringMsg,
            std_srvs::srv::{SetBool, SetBool_Request, SetBool_Response},
        },
        interfaces::rcl_interfaces::msg::Log,
        msg::RosString,
    },
    prelude::*,
};
use zenoh::{
    handlers::RingChannel,
    key_expr::format::{kedefine, keformat},
};
use zenoh_ext::AdvancedSubscriberBuilderExt;

use robot_control::kinematics::WHEELS;

kedefine!(pub(crate) topic_keyexpr: "${domain:*}/${topic:**}/${dds_type:*}/${hash:*}");

fn read_mesh_asset(uri: &str) -> Result<Vec<u8>, String> {
    let filename = uri
        .strip_prefix(MESH_URI_PREFIX)
        .filter(|name| !name.is_empty() && !name.contains('/') && !name.contains(".."))
        .ok_or_else(|| format!("unknown asset {uri}"))?;
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("robot_description")
        .join("meshes")
        .join(filename);
    fs::read(&path).map_err(|error| format!("read {}: {error}", path.display()))
}

const RING_CHANNEL_CAPACITY: usize = 16;
const BIND_ADDRESS: &str = "0.0.0.0";
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

fn wheel_transforms(now: &Timestamp, joint_states: &JointState) -> Vec<FrameTransform> {
    WHEELS
        .iter()
        .filter_map(|wheel| {
            let angle = joint_states
                .name
                .iter()
                .zip(joint_states.position.iter())
                .find(|(name, _)| name.get_string() == wheel.joint_name)
                .map(|(_, position)| *position)?;
            let (sin, cos) = (angle / 2.0).sin_cos();
            let offset = wheel_offset_from_motor(wheel.corner.side()) * MM_TO_M;
            Some(transform(
                now,
                wheel.corner.motor_link().urdf_name(),
                wheel.corner.wheel_link().urdf_name(),
                (offset.x, offset.y, offset.z),
                (0.0, sin, 0.0, cos),
            ))
        })
        .collect()
}

struct CachedChannel {
    channel: Arc<RawChannel>,
    last_payload: Vec<u8>,
}

type LastValues = Arc<Mutex<HashMap<ChannelId, CachedChannel>>>;

const TELEOP_REPUBLISH_PERIOD: Duration = Duration::from_millis(50);

enum TeleopEvent {
    Command(f64, f64),
    Stop,
}

struct BridgeListener {
    teleop_tx: tokio::sync::mpsc::UnboundedSender<TeleopEvent>,
    webcam: robot_sensors::WebcamSink,
    last_values: LastValues,
}

impl ServerListener for BridgeListener {
    fn on_message_data(&self, _client: Client, channel: &ClientChannel, payload: &[u8]) {
        if channel.topic.contains("cmd_vel") {
            if let Some(twist) = decode_twist(&channel.encoding, payload) {
                let _ = self
                    .teleop_tx
                    .send(TeleopEvent::Command(twist.linear.x, twist.angular.z));
            }
            return;
        }
        if channel.topic.contains("image") {
            self.webcam
                .accept(&channel.topic, &channel.encoding, payload);
        }
    }

    fn on_client_advertise(&self, _client: Client, channel: &ClientChannel) {
        tracing::debug!(
            topic = %channel.topic,
            encoding = %channel.encoding,
            schema_name = %channel.schema_name,
            "client advertised channel"
        );
    }

    fn on_client_unadvertise(&self, _client: Client, channel: &ClientChannel) {
        if channel.topic.contains("cmd_vel") {
            let _ = self.teleop_tx.send(TeleopEvent::Stop);
        }
    }

    fn on_client_disconnect(&self) {
        let _ = self.teleop_tx.send(TeleopEvent::Stop);
    }

    fn on_subscribe(&self, client: Client, channel: ChannelView) {
        if let Some(cached) = self.last_values.lock().unwrap().get(&channel.id()) {
            if !cached.last_payload.is_empty() {
                cached
                    .channel
                    .log_to_sink(cached.last_payload.as_slice(), client.sink_id());
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
        "geometry_msgs/msg/TwistStamped" => TwistStamped::type_description(),
        "std_msgs/msg/String" => StringMsg::type_description(),
        "rcl_interfaces/msg/Log" => Log::type_description(),
        _ => return None,
    };
    Some(rewrite_schema_headers(description.to_msg_definition()))
}

const ENABLE_SERVICES: [&str; 3] = [
    "/line_follower/enable",
    "/row_follower/enable",
    "/gesture/enable",
];

struct EnableCall {
    service: String,
    data: bool,
    respond: tokio::sync::oneshot::Sender<Result<(bool, String), String>>,
}

fn parse_enable(payload: &[u8]) -> Result<bool, String> {
    <SetBool_Request as TypeSupport>::from_bytes(payload)
        .map(|request| request.data)
        .map_err(|error| format!("invalid request: {error}"))
}

fn enable_response(success: bool, message: &str) -> Result<Vec<u8>, String> {
    let mut response = SetBool_Response::new().ok_or("failed to build response")?;
    response.success = success;
    response.message = RosString::new(message).ok_or("invalid response message")?;
    response.to_bytes().map_err(|error| error.to_string())
}

fn ros2_schema(ros_type: &str, definition: String) -> foxglove::Schema {
    foxglove::Schema::new(ros_type, "ros2msg", rewrite_schema_headers(definition).into_bytes())
}

fn set_bool_schema() -> ServiceSchema {
    ServiceSchema::new("std_srvs/srv/SetBool")
        .with_request(
            "cdr",
            ros2_schema(
                "std_srvs/srv/SetBool_Request",
                SetBool_Request::type_description().to_msg_definition(),
            ),
        )
        .with_response(
            "cdr",
            ros2_schema(
                "std_srvs/srv/SetBool_Response",
                SetBool_Response::type_description().to_msg_definition(),
            ),
        )
}

fn enable_service(name: &str, enable_tx: tokio::sync::mpsc::UnboundedSender<EnableCall>) -> Service {
    Service::builder(name, set_bool_schema()).async_handler_fn(
        move |request| {
            let enable_tx = enable_tx.clone();
            async move {
                let data = parse_enable(request.payload())?;
                let (respond, response) = tokio::sync::oneshot::channel();
                enable_tx
                    .send(EnableCall {
                        service: request.service_name().to_string(),
                        data,
                        respond,
                    })
                    .map_err(|_| "enable worker stopped".to_string())?;
                let (success, message) = response
                    .await
                    .map_err(|_| "no response from enable worker".to_string())??;
                enable_response(success, &message)
            }
        },
    )
}

pub async fn run_bridge(
    node: Arc<Node>,
    port: u16,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let context = node.context().clone();

    let (teleop_tx, mut teleop_rx) = tokio::sync::mpsc::unbounded_channel::<TeleopEvent>();
    let last_values: LastValues = Arc::new(Mutex::new(HashMap::new()));
    let webcam = robot_sensors::spawn_webcam_forwarder(&node)?;
    let (enable_tx, mut enable_rx) = tokio::sync::mpsc::unbounded_channel::<EnableCall>();
    let server = foxglove::WebSocketServer::new()
        .name("bridge")
        .bind(BIND_ADDRESS, port)
        .capabilities([Capability::ClientPublish, Capability::ConnectionGraph])
        .supported_encodings(["json", "cdr"])
        .services(ENABLE_SERVICES.map(|name| enable_service(name, enable_tx.clone())))
        .listener(Arc::new(BridgeListener {
            teleop_tx,
            webcam,
            last_values: last_values.clone(),
        }))
        .fetch_asset_handler_blocking_fn(|_client, uri| read_mesh_asset(&uri))
        .start()
        .await?;
    tracing::info!("bridge live: ws://{BIND_ADDRESS}:{port}");

    let enable_node = node.clone();
    tokio::spawn(async move {
        let mut line = enable_node
            .create_client::<SetBool>("/line_follower/enable", None)
            .ok();
        let mut row = enable_node
            .create_client::<SetBool>("/row_follower/enable", None)
            .ok();
        let mut gesture = enable_node
            .create_client::<SetBool>("/gesture/enable", None)
            .ok();
        while let Some(call) = enable_rx.recv().await {
            let client = match call.service.as_str() {
                "/line_follower/enable" => line.as_mut(),
                "/row_follower/enable" => row.as_mut(),
                "/gesture/enable" => gesture.as_mut(),
                _ => None,
            };
            let result = match client {
                None => Err(format!("no client for {}", call.service)),
                Some(client) => {
                    let mut request = SetBool_Request::new().unwrap();
                    request.data = call.data;
                    match tokio::time::timeout(Duration::from_secs(2), client.call(&request)).await {
                        Ok(Ok(message)) => {
                            Ok((message.sample.success, message.sample.message.to_string()))
                        }
                        Ok(Err(error)) => Err(error.to_string()),
                        Err(_) => Err("service call timed out".to_string()),
                    }
                }
            };
            let _ = call.respond.send(result);
        }
    });

    let cmd_vel_pub = node.create_publisher::<TwistStamped>("cmd_vel", Some(Profile { depth: 1, ..Profile::sensor_data() }))?;
    tokio::spawn(async move {
        let mut command: Option<(f64, f64)> = None;
        let mut tick = tokio::time::interval(TELEOP_REPUBLISH_PERIOD);
        loop {
            tokio::select! {
                event = teleop_rx.recv() => match event {
                    Some(TeleopEvent::Command(linear, angular)) => {
                        command = Some((linear, angular));
                    }
                    Some(TeleopEvent::Stop) => {
                        command = None;
                        let _ = cmd_vel_pub.send(&stamped_twist(0.0, 0.0));
                    }
                    None => break,
                },
                _ = tick.tick() => {
                    if let Some((linear, angular)) = command {
                        let _ = cmd_vel_pub.send(&stamped_twist(linear, angular));
                    }
                }
            }
        }
    });

    let mut odom_sub = node.create_subscriber::<Odometry>("odom", None)?;
    let mut joint_state_sub = node.create_subscriber::<JointState>("joint_states", None)?;
    let tf_channel = Arc::new(foxglove::ChannelBuilder::new("/tf").build::<FrameTransforms>());
    let wheel_tf_channel = tf_channel.clone();
    tokio::spawn(async move {
        while let Ok(message) = odom_sub.recv().await {
            let now = Timestamp::now();
            let transforms = vec![base_link_transform(&now, &message.sample.pose.pose)];
            tf_channel.log(&FrameTransforms { transforms });
        }
    });
    tokio::spawn(async move {
        while let Ok(message) = joint_state_sub.recv().await {
            let now = Timestamp::now();
            let transforms = wheel_transforms(&now, &message.sample);
            wheel_tf_channel.log(&FrameTransforms { transforms });
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
                        .insert(
                            channel_id,
                            CachedChannel {
                                channel: channel.clone(),
                                last_payload: Vec::new(),
                            },
                        );

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
                            if let Some(cached) = last_values.lock().unwrap().get_mut(&channel_id) {
                                cached.last_payload.clear();
                                cached.last_payload.extend_from_slice(bytes.as_ref());
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
