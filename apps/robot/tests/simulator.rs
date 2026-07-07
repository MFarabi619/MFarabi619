use std::{
    error::Error,
    sync::{Arc, Mutex},
    time::Duration,
};

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

#[tokio::test(flavor = "multi_thread")]
async fn drives_on_cmd_vel_then_halts_after_deadman() -> Result<(), Box<dyn Error + Send + Sync>> {
    let ctx = Context::new()?;
    let sim_node = ctx.create_node("sim", None)?;
    let test_node = ctx.create_node("tester", None)?;

    // The simulator runs in-process on the same session — no cross-process discovery.
    let sim = tokio::spawn(robot::run_simulator(sim_node));

    let cmd_pub = test_node.create_publisher::<Twist>("cmd_vel", None)?;
    let mut gps =
        test_node.create_subscriber::<NavSatFix>("gps/fix", Some(Profile::sensor_data()))?;

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
            let _ = cmd_pub.send(&twist);
        }
    });

    tokio::time::sleep(Duration::from_millis(800)).await;
    let longitude_driving_start = *latest_longitude.lock().unwrap();
    tokio::time::sleep(Duration::from_millis(1000)).await;
    let longitude_driving_end = *latest_longitude.lock().unwrap();
    assert!(
        longitude_driving_start.is_finite(),
        "expected gps data while driving"
    );
    assert!(
        longitude_driving_end != longitude_driving_start,
        "robot should move while commanded (start={longitude_driving_start}, end={longitude_driving_end})"
    );

    driver.abort();
    tokio::time::sleep(Duration::from_secs_f64(DEADMAN_SECONDS + 0.8)).await;
    let longitude_after_halt_start = *latest_longitude.lock().unwrap();
    tokio::time::sleep(Duration::from_millis(600)).await;
    let longitude_after_halt_end = *latest_longitude.lock().unwrap();
    assert_eq!(
        longitude_after_halt_start, longitude_after_halt_end,
        "robot should be halted after the deadman (start={longitude_after_halt_start}, end={longitude_after_halt_end})"
    );

    let mut client = test_node.create_client::<SetParameters>("/sim/set_parameters", None)?;
    for _ in 0..50 {
        if client.is_service_available() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    let set_deadman = |value: f64| -> SetParameters_Request {
        let mut req = SetParameters_Request::new().unwrap();
        let mut param = Parameter::new().unwrap();
        param.name = RosString::new("deadman_seconds").unwrap();
        param.value.r#type = ParameterType::PARAMETER_DOUBLE;
        param.value.double_value = value;
        let mut seq = ParameterSeq::<0>::new(1).unwrap();
        seq.as_mut_slice()[0] = param;
        req.parameters = seq;
        req
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

    sim.abort();
    watcher.abort();
    Ok(())
}
