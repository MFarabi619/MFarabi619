use std::{sync::Arc, time::Duration};

use oxidros::{
    msg::{
        common_interfaces::sensor_msgs::msg::{NavSatFix, NavSatStatus},
        msg::RosString,
    },
    prelude::*,
};
use robot_control::params::string_param;
use robot_description::time::now_stamp;
use robot_description::frames::BASE_LINK;
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::TcpStream,
    time::sleep,
};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const GPSD_PORT: u16 = 2947;
const WATCH_COMMAND: &[u8] = b"?WATCH={\"enable\":true,\"json\":true}\r\n";
const RECONNECT_DELAY: Duration = Duration::from_secs(2);
const FIX_MODE_2D: i64 = 2;

fn tpv_to_fix(report: &serde_json::Value) -> Option<NavSatFix> {
    if report["mode"].as_i64().unwrap_or(0) < FIX_MODE_2D {
        return None;
    }
    let latitude = report["lat"].as_f64()?;
    let longitude = report["lon"].as_f64()?;
    let (sec, nanosec) = now_stamp();
    let mut fix = NavSatFix::new().unwrap();
    fix.header.stamp.sec = sec;
    fix.header.stamp.nanosec = nanosec;
    fix.header.frame_id = RosString::new(BASE_LINK).unwrap();
    fix.status.status = NavSatStatus::STATUS_FIX;
    fix.status.service = NavSatStatus::SERVICE_GPS;
    fix.latitude = latitude;
    fix.longitude = longitude;
    fix.altitude = report["altHAE"].as_f64().unwrap_or(0.0);
    let east_variance = report["epx"].as_f64().unwrap_or(0.0).powi(2);
    let north_variance = report["epy"].as_f64().unwrap_or(0.0).powi(2);
    let up_variance = report["epv"].as_f64().unwrap_or(0.0).powi(2);
    fix.position_covariance = [
        east_variance,
        0.0,
        0.0,
        0.0,
        north_variance,
        0.0,
        0.0,
        0.0,
        up_variance,
    ];
    fix.position_covariance_type = NavSatFix::COVARIANCE_TYPE_DIAGONAL_KNOWN;
    Some(fix)
}

async fn stream_fixes(publisher: &Publisher<NavSatFix>, host: &str) -> Result<(), BoxError> {
    let mut stream = TcpStream::connect((host, GPSD_PORT)).await?;
    stream.write_all(WATCH_COMMAND).await?;
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    loop {
        line.clear();
        if reader.read_line(&mut line).await? == 0 {
            return Ok(());
        }
        let Ok(report) = serde_json::from_str::<serde_json::Value>(&line) else {
            continue;
        };
        if report["class"] == "TPV" {
            if let Some(fix) = tpv_to_fix(&report) {
                publisher.send(&fix)?;
            }
        }
    }
}

pub async fn run_gps(node: Arc<Node>, default_host: &str) -> Result<(), BoxError> {
    let host = {
        let parameters = node.create_parameter_server()?;
        let store = parameters.params.read();
        string_param(&store, "host", default_host)
    };
    let publisher = node.create_publisher::<NavSatFix>("gps/fix", Some(Profile::sensor_data()))?;
    tracing::info!("reading gpsd at {host}:{GPSD_PORT}");
    loop {
        if let Err(error) = stream_fixes(&publisher, &host).await {
            tracing::warn!("gpsd connection lost ({error}); retrying");
        }
        sleep(RECONNECT_DELAY).await;
    }
}
