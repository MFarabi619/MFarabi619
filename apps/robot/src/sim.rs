use std::{
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use oxidros::{
    msg::{
        common_interfaces::{
            diagnostic_msgs::msg::{
                DiagnosticArray, DiagnosticStatus, DiagnosticStatusSeq, KeyValue, KeyValueSeq,
            },
            geometry_msgs::msg::Twist,
            nav_msgs::msg::Odometry,
            sensor_msgs::msg::{BatteryState, CameraInfo, Image, NavSatFix, NavSatStatus},
            std_msgs::msg::String as StringMsg,
        },
        msg::{F64Seq, RosString, U8Seq},
    },
    prelude::*,
};
use tokio::time::interval;

use crate::{
    battery_diagnostic_level, command_is_stale, enu_to_geodetic,
    frames::{BASE_LINK, CAMERA_OPTICAL, ODOM},
    integrate_pose, intrinsics, render_field,
};

const IMAGE_WIDTH: usize = 640;
const IMAGE_HEIGHT: usize = 400;
const CAMERA_FOV_DEG: f64 = 70.0;
const CAMERA_HEIGHT: f64 = 0.2;
const LATITUDE_ORIGIN: f64 = 45.4215;
const LONGITUDE_ORIGIN: f64 = -75.6972;
const PHYSICS_HZ: f64 = 50.0;
pub const DEADMAN_SECONDS: f64 = 2.0;
const ROBOT_URDF: &str = include_str!("../urdf/robot.urdf");
const CAMERA_HZ: f64 = 15.0;
const GPS_HZ: f64 = 5.0;
const ODOM_HZ: f64 = 30.0;
const BATTERY_HZ: f64 = 1.0;
const BATTERY_IDLE_DRAIN: f64 = 0.02;
const BATTERY_MOTION_DRAIN: f64 = 0.5;
const BATTERY_MIN_VOLTAGE: f64 = 11.5;
const BATTERY_VOLTAGE_SPAN: f64 = 1.2;

fn now_stamp() -> (i32, u32) {
    let since = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    (since.as_secs() as i32, since.subsec_nanos())
}

#[derive(Default)]
struct SimState {
    x: f64,
    y: f64,
    theta: f64,
    linear: f64,
    angular: f64,
    battery_percent: f64,
}

impl SimState {
    fn new() -> Self {
        SimState {
            battery_percent: 100.0,
            ..Default::default()
        }
    }

    fn set_command(&mut self, twist: &Twist) {
        self.linear = twist.linear.x;
        self.angular = twist.angular.z;
    }

    fn stop(&mut self) {
        self.linear = 0.0;
        self.angular = 0.0;
    }

    fn integrate(&mut self, dt: f64) {
        (self.x, self.y, self.theta) =
            integrate_pose(self.x, self.y, self.theta, self.linear, self.angular, dt);
    }

    fn speed(&self) -> f64 {
        self.linear.abs() + self.angular.abs()
    }

    fn camera(&self) -> (Image, CameraInfo) {
        let (sec, nanosec) = now_stamp();
        let (fx, fy, cx, cy) = intrinsics(IMAGE_WIDTH, IMAGE_HEIGHT, CAMERA_FOV_DEG);
        let frame = render_field(
            self.x,
            self.y,
            self.theta,
            IMAGE_WIDTH,
            IMAGE_HEIGHT,
            CAMERA_FOV_DEG,
            CAMERA_HEIGHT,
        );

        let mut image = Image::new().unwrap();
        image.header.stamp.sec = sec;
        image.header.stamp.nanosec = nanosec;
        image.header.frame_id = RosString::new(CAMERA_OPTICAL).unwrap();
        image.height = IMAGE_HEIGHT as u32;
        image.width = IMAGE_WIDTH as u32;
        image.encoding = RosString::new("rgb8").unwrap();
        image.is_bigendian = 0;
        image.step = (IMAGE_WIDTH * 3) as u32;
        let mut data = U8Seq::new(frame.len()).unwrap();
        data.as_mut_slice().copy_from_slice(&frame);
        image.data = data;

        let mut info = CameraInfo::new().unwrap();
        info.header.stamp.sec = sec;
        info.header.stamp.nanosec = nanosec;
        info.header.frame_id = RosString::new(CAMERA_OPTICAL).unwrap();
        info.width = IMAGE_WIDTH as u32;
        info.height = IMAGE_HEIGHT as u32;
        info.distortion_model = RosString::new("plumb_bob").unwrap();
        info.d = F64Seq::new(5).unwrap();
        info.k = [fx, 0.0, cx, 0.0, fy, cy, 0.0, 0.0, 1.0];
        info.r = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
        info.p = [fx, 0.0, cx, 0.0, 0.0, fy, cy, 0.0, 0.0, 0.0, 1.0, 0.0];

        (image, info)
    }

    fn gps(&self, lat_origin: f64, lon_origin: f64) -> NavSatFix {
        let (sec, nanosec) = now_stamp();
        let (latitude, longitude) = enu_to_geodetic(self.x, self.y, lat_origin, lon_origin);
        let mut fix = NavSatFix::new().unwrap();
        fix.header.stamp.sec = sec;
        fix.header.stamp.nanosec = nanosec;
        fix.header.frame_id = RosString::new(BASE_LINK).unwrap();
        fix.status.status = NavSatStatus::STATUS_FIX;
        fix.status.service = NavSatStatus::SERVICE_GPS;
        fix.latitude = latitude;
        fix.longitude = longitude;
        fix.altitude = 0.0;
        fix.position_covariance = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 4.0];
        fix.position_covariance_type = NavSatFix::COVARIANCE_TYPE_DIAGONAL_KNOWN;
        fix
    }

    fn odom(&self) -> Odometry {
        let (sec, nanosec) = now_stamp();
        let mut odom = Odometry::new().unwrap();
        odom.header.stamp.sec = sec;
        odom.header.stamp.nanosec = nanosec;
        odom.header.frame_id = RosString::new(ODOM).unwrap();
        odom.child_frame_id = RosString::new(BASE_LINK).unwrap();
        odom.pose.pose.position.x = self.x;
        odom.pose.pose.position.y = self.y;
        odom.pose.pose.orientation.z = (self.theta / 2.0).sin();
        odom.pose.pose.orientation.w = (self.theta / 2.0).cos();
        odom.twist.twist.linear.x = self.linear;
        odom.twist.twist.angular.z = self.angular;
        odom
    }

    fn step_battery(&mut self) -> BatteryState {
        self.battery_percent = (self.battery_percent
            - (BATTERY_IDLE_DRAIN + BATTERY_MOTION_DRAIN * self.speed()))
        .max(0.0);
        let (sec, nanosec) = now_stamp();
        let mut battery = BatteryState::new().unwrap();
        battery.header.stamp.sec = sec;
        battery.header.stamp.nanosec = nanosec;
        battery.voltage =
            (BATTERY_MIN_VOLTAGE + BATTERY_VOLTAGE_SPAN * (self.battery_percent / 100.0)) as f32;
        battery.percentage = (self.battery_percent / 100.0) as f32;
        battery.power_supply_status = BatteryState::POWER_SUPPLY_STATUS_DISCHARGING;
        battery.present = true;
        battery
    }

    fn diagnostics(&self) -> DiagnosticArray {
        let (sec, nanosec) = now_stamp();
        let mut array = DiagnosticArray::new().unwrap();
        array.header.stamp.sec = sec;
        array.header.stamp.nanosec = nanosec;

        let percentage_text = format!("{:.0}%", self.battery_percent);

        let mut kv = KeyValue::new().unwrap();
        kv.key = RosString::new("percentage").unwrap();
        kv.value = RosString::new(&percentage_text).unwrap();
        let values = KeyValueSeq::<0>::from_vec(vec![kv]).unwrap();

        let mut status = DiagnosticStatus::new().unwrap();
        status.level = battery_diagnostic_level(self.battery_percent);
        status.name = RosString::new("battery").unwrap();
        status.hardware_id = RosString::new("simulator").unwrap();
        status.message = RosString::new(&percentage_text).unwrap();
        status.values = values;

        array.status = DiagnosticStatusSeq::<0>::from_vec(vec![status]).unwrap();

        array
    }
}

pub async fn run_simulator(
    node: Arc<Node>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut cmd_vel = node.create_subscriber::<Twist>("cmd_vel", None)?;
    let image_pub =
        node.create_publisher::<Image>("camera/image_raw", Some(Profile::sensor_data()))?;
    let camera_info_pub =
        node.create_publisher::<CameraInfo>("camera/camera_info", Some(Profile::sensor_data()))?;
    let gps_pub = node.create_publisher::<NavSatFix>("gps/fix", Some(Profile::sensor_data()))?;
    let battery_pub = node.create_publisher::<BatteryState>("battery", None)?;
    let diag_pub = node.create_publisher::<DiagnosticArray>("/diagnostics", None)?;
    let odom_pub = node.create_publisher::<Odometry>("odom", None)?;
    let robot_description_pub = node.create_publisher::<StringMsg>("robot_description", None)?;

    let mut param_server = node.create_parameter_server()?;
    {
        let mut params = param_server.params.write();
        params.set_parameter(
            "deadman_seconds".to_string(),
            Value::F64(DEADMAN_SECONDS),
            false,
            Some("Halt the robot if no cmd_vel arrives within this many seconds".to_string()),
        )?;
        params.set_floating_point_range("deadman_seconds", 0.1, 60.0, 0.0)?;
        params.set_parameter(
            "latitude_origin".to_string(),
            Value::F64(LATITUDE_ORIGIN),
            false,
            Some("GPS origin latitude in degrees".to_string()),
        )?;
        params.set_parameter(
            "longitude_origin".to_string(),
            Value::F64(LONGITUDE_ORIGIN),
            false,
            Some("GPS origin longitude in degrees".to_string()),
        )?;
    }
    let params = param_server.params.clone();
    let read_f64 = |name: &str, fallback: f64| -> f64 {
        if let Some(p) = params.read().get_parameter(name) {
            if let Value::F64(v) = p.value {
                return v;
            }
            tracing::warn!("parameter '{name}' is not an f64; keeping {fallback}");
        }
        fallback
    };
    let mut deadman_seconds = read_f64("deadman_seconds", DEADMAN_SECONDS);
    let mut lat_origin = read_f64("latitude_origin", LATITUDE_ORIGIN);
    let mut lon_origin = read_f64("longitude_origin", LONGITUDE_ORIGIN);

    let mut state = SimState::new();
    let mut last_command = Instant::now();
    let dt = 1.0 / PHYSICS_HZ;
    let mut physics_tick = interval(Duration::from_secs_f64(dt));
    let mut camera_tick = interval(Duration::from_secs_f64(1.0 / CAMERA_HZ));
    let mut gps_tick = interval(Duration::from_secs_f64(1.0 / GPS_HZ));
    let mut battery_tick = interval(Duration::from_secs_f64(1.0 / BATTERY_HZ));
    let mut odom_tick = interval(Duration::from_secs_f64(1.0 / ODOM_HZ));

    tracing::info!("driving on cmd_vel -> camera/gps/battery");
    let ctrl_c = tokio::signal::ctrl_c();
    tokio::pin!(ctrl_c);
    loop {
        tokio::select! {
            _ = &mut ctrl_c => break,
            updated = param_server.wait() => {
                match updated {
                    Ok(names) => {
                        for name in &names {
                            tracing::info!("parameter '{name}' updated");
                        }
                        deadman_seconds = read_f64("deadman_seconds", deadman_seconds);
                        lat_origin = read_f64("latitude_origin", lat_origin);
                        lon_origin = read_f64("longitude_origin", lon_origin);
                    }
                    Err(e) => tracing::warn!("parameter service error: {e}"),
                }
            }
            message = cmd_vel.recv() => {
                state.set_command(&message?.sample);
                last_command = Instant::now();
            }
            _ = physics_tick.tick() => {
                if command_is_stale(last_command.elapsed().as_secs_f64(), deadman_seconds) {
                    state.stop();
                }
                state.integrate(dt);
            }
            _ = camera_tick.tick() => {
                let (image, info) = state.camera();
                image_pub.send(&image)?;
                camera_info_pub.send(&info)?;
            }
            _ = gps_tick.tick() => gps_pub.send(&state.gps(lat_origin, lon_origin))?,
            _ = odom_tick.tick() => odom_pub.send(&state.odom())?,
            _ = battery_tick.tick() => {
                battery_pub.send(&state.step_battery())?;
                diag_pub.send(&state.diagnostics())?;
                let mut description = StringMsg::new().unwrap();
                description.data = RosString::new(ROBOT_URDF).unwrap();
                robot_description_pub.send(&description)?;
            }
        }
    }

    tracing::info!("shutting down");
    Ok(())
}
