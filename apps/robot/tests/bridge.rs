use std::{error::Error, time::Duration};

use foxglove::ws_protocol::server::ServerMessage;
use futures_util::StreamExt;
use oxidros::prelude::*;
use tokio_tungstenite::tungstenite::{client::IntoClientRequest, http::HeaderValue, Message};

const TEST_PORT: u16 = 8799;
const SUBPROTOCOL: &str = "foxglove.sdk.v1";
const ISOLATED_DOMAIN: &str = "77";

// End-to-end: sim publishes -> bridge discovers + advertises over a real websocket -> a
// foxglove client reads the advertised schema. Regression guard for the Lichtblick schema-header break.
#[tokio::test(flavor = "multi_thread")]
async fn bridge_advertises_a_self_consistent_gps_schema() -> Result<(), Box<dyn Error + Send + Sync>>
{
    // Isolate on a unique domain so this can't collide with tests/simulator.rs on the fabric.
    std::env::set_var("ROS_DOMAIN_ID", ISOLATED_DOMAIN);

    let ctx = Context::new()?;
    let sim_node = ctx.create_node("sim", None)?;
    let bridge_node = ctx.create_node("bridge", None)?;
    let sim = tokio::spawn(robot::run_simulator(sim_node));
    let bridge = tokio::spawn(robot::run_bridge(bridge_node, TEST_PORT));

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

    sim.abort();
    bridge.abort();
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
