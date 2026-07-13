use std::{
    error::Error,
    sync::{Arc, Mutex},
    time::Duration,
};

use foxglove::ws_protocol::server::ServerMessage;
use futures_util::StreamExt;
use oxidros::{
    msg::{
        common_interfaces::{geometry_msgs::msg::Twist, sensor_msgs::msg::NavSatFix},
        interfaces::rcl_interfaces::{
            msg::{Parameter, ParameterSeq, ParameterType},
            srv::{SetParameters, SetParameters_Request},
        },
        msg::RosString,
    },
    prelude::*,
};
use robot::simulator::DEADMAN_SECONDS;
use tokio_tungstenite::tungstenite::{client::IntoClientRequest, http::HeaderValue, Message};

type BoxError = Box<dyn Error + Send + Sync>;

const TEST_PORT: u16 = 8799;
const ISOLATED_DOMAIN: u32 = 77;
const SUBPROTOCOL: &str = "foxglove.sdk.v1";

#[tokio::main]
async fn main() -> Result<(), BoxError> {
    let context = Context::with_domain_id(ISOLATED_DOMAIN)?;
    let sim_node = context.create_node("sim", None)?;
    let bridge_node = context.create_node("bridge", None)?;
    let test_node = context.create_node("tester", None)?;

    let sim = tokio::spawn(robot::run_simulator(sim_node, robot::Scene::Field));
    let bridge = tokio::spawn(robot::run_bridge(bridge_node, TEST_PORT));

    bridge_advertises_a_self_consistent_schema().await?;
    drives_on_cmd_vel_then_halts_after_deadman(&test_node).await?;
    rejects_an_out_of_range_deadman_parameter(&test_node).await?;

    sim.abort();
    bridge.abort();
    println!("e2e: all stages passed");
    Ok(())
}

async fn bridge_advertises_a_self_consistent_schema() -> Result<(), BoxError> {
    println!("-- stage 1: bridge advertises a self-consistent gps/fix schema");

    let mut stream = None;
    for _ in 0..50 {
        let mut request = format!("ws://127.0.0.1:{TEST_PORT}/").into_client_request()?;
        request.headers_mut().insert(
            "sec-websocket-protocol",
            HeaderValue::from_static(SUBPROTOCOL),
        );
        if let Ok((socket, _)) = tokio_tungstenite::connect_async(request).await {
            stream = Some(socket);
            break;
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
    }
    let mut stream = stream.expect("bridge websocket server never came up");

    let gps_schema = tokio::time::timeout(Duration::from_secs(15), async {
        while let Some(Ok(msg)) = stream.next().await {
            let Message::Text(text) = msg else {
                continue;
            };
            if let Ok(ServerMessage::Advertise(advertise)) = ServerMessage::parse_json(&text) {
                for channel in advertise.channels {
                    if channel.topic.contains("gps/fix") {
                        return channel.schema.into_owned();
                    }
                }
            }
        }
        panic!("stream ended before gps/fix was advertised");
    })
    .await
    .expect("timed out waiting for the gps/fix advertisement");

    // Every field-referenced complex type must have a matching `MSG:` block. The bug was that
    // `MSG: std_msgs/msg/Header` (3-part) didn't match the field reference `std_msgs/Header`.
    let (referenced, defined) = referenced_and_defined(&gps_schema);
    assert!(
        referenced.contains(&"std_msgs/Header".to_string()),
        "expected NavSatFix to reference std_msgs/Header:\n{gps_schema}"
    );
    for name in &referenced {
        assert!(
            defined.contains(name),
            "schema references '{name}' but has no matching 'MSG: {name}' block:\n{gps_schema}"
        );
    }
    println!("   ok");
    Ok(())
}

async fn drives_on_cmd_vel_then_halts_after_deadman(node: &Arc<Node>) -> Result<(), BoxError> {
    println!("-- stage 2: drives on cmd_vel, halts after the deadman");

    let cmd_vel_publisher = node.create_publisher::<Twist>("cmd_vel", None)?;
    let mut gps = node.create_subscriber::<NavSatFix>("gps/fix", Some(Profile::sensor_data()))?;

    let latest_longitude = Arc::new(Mutex::new(f64::NAN));
    let watcher = {
        let latest_longitude = latest_longitude.clone();
        tokio::spawn(async move {
            while let Ok(fix) = gps.recv().await {
                *latest_longitude.lock().unwrap() = fix.sample.longitude;
            }
        })
    };

    let driver = tokio::spawn(async move {
        let mut twist = Twist::new().unwrap();
        twist.linear.x = 5.0;
        let mut tick = tokio::time::interval(Duration::from_millis(100));
        loop {
            tick.tick().await;
            let _ = cmd_vel_publisher.send(&twist);
        }
    });

    tokio::time::sleep(Duration::from_millis(800)).await;
    let driving_start = *latest_longitude.lock().unwrap();
    tokio::time::sleep(Duration::from_millis(1000)).await;
    let driving_end = *latest_longitude.lock().unwrap();
    assert!(driving_start.is_finite(), "expected gps data while driving");
    assert!(
        driving_end != driving_start,
        "robot should move while commanded (start={driving_start}, end={driving_end})"
    );

    driver.abort();
    tokio::time::sleep(Duration::from_secs_f64(DEADMAN_SECONDS + 0.8)).await;
    let halt_start = *latest_longitude.lock().unwrap();
    tokio::time::sleep(Duration::from_millis(600)).await;
    let halt_end = *latest_longitude.lock().unwrap();
    assert_eq!(
        halt_start, halt_end,
        "robot should be halted after the deadman (start={halt_start}, end={halt_end})"
    );

    watcher.abort();
    println!("   ok");
    Ok(())
}

async fn rejects_an_out_of_range_deadman_parameter(node: &Arc<Node>) -> Result<(), BoxError> {
    println!("-- stage 3: rejects an out-of-range deadman parameter");

    let mut client = node.create_client::<SetParameters>("/sim/set_parameters", None)?;
    for _ in 0..50 {
        if client.is_service_available() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    let set_deadman = |value: f64| -> SetParameters_Request {
        let mut request = SetParameters_Request::new().unwrap();
        let mut param = Parameter::new().unwrap();
        param.name = RosString::new("deadman_seconds").unwrap();
        param.value.r#type = ParameterType::PARAMETER_DOUBLE;
        param.value.double_value = value;
        let mut seq = ParameterSeq::<0>::new(1).unwrap();
        seq.as_mut_slice()[0] = param;
        request.parameters = seq;
        request
    };
    let accepted = client.call(&set_deadman(0.5)).await?;
    assert!(
        accepted.sample.results.as_slice()[0].successful,
        "runtime set of deadman_seconds should be accepted"
    );
    let rejected = client.call(&set_deadman(-5.0)).await?;
    assert!(
        !rejected.sample.results.as_slice()[0].successful,
        "out-of-range deadman_seconds should be rejected by the range"
    );
    println!("   ok");
    Ok(())
}

fn referenced_and_defined(schema: &str) -> (Vec<String>, Vec<String>) {
    let mut defined = Vec::new();
    let mut referenced = Vec::new();
    for line in schema.lines() {
        let line = line.trim();
        if let Some(name) = line.strip_prefix("MSG: ") {
            defined.push(name.to_string());
        } else if !line.is_empty() && !line.starts_with('=') && !line.starts_with('#') {
            if let Some(field_type) = line.split_whitespace().next() {
                let base = field_type.split('[').next().unwrap_or(field_type);
                if base.contains('/') {
                    referenced.push(base.to_string());
                }
            }
        }
    }
    (referenced, defined)
}
