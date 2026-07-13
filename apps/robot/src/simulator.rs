use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use description::{placement, MM_TO_M};
use oxidros::{
    msg::{
        common_interfaces::{
            diagnostic_msgs::msg::DiagnosticArray,
            geometry_msgs::msg::Twist,
            nav_msgs::msg::Odometry,
            sensor_msgs::msg::{
                BatteryState, CameraInfo, CompressedImage, JointState, NavSatFix, NavSatStatus,
            },
        },
        msg::{F64Seq, RosString},
    },
    prelude::*,
};
use tokio::time::interval;

use crate::{
    camera_intrinsics, command_is_stale,
    diagnostics::{battery_diagnostic_level, diagnostic_array, Status},
    enu_to_geodetic,
    frames::{BASE_LINK, CAMERA_OPTICAL, ODOM},
    integrate_pose,
    kinematics::wheel_angular_velocities,
    now_stamp,
    odometry::joint_state_message,
    qos, CameraRenderer, Scene,
};

const IMAGE_WIDTH: usize = 1280;
const IMAGE_HEIGHT: usize = 800;
const CAMERA_FOV_DEG: f64 = 70.0;
const GPS_POSITION_COVARIANCE: [f64; 9] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 4.0];
const JPEG_QUALITY: u8 = 80;
const LATITUDE_ORIGIN: f64 = 45.4215;
const LONGITUDE_ORIGIN: f64 = -75.6972;
const PHYSICS_HZ: f64 = 50.0;
pub const DEADMAN_SECONDS: f64 = 2.0;
const DEADMAN_MIN_SECONDS: f64 = 0.0;
const DEADMAN_MAX_SECONDS: f64 = 60.0;
const CAMERA_HZ: f64 = 15.0;
const GPS_HZ: f64 = 5.0;
const ODOMETRY_HZ: f64 = 30.0;
const BATTERY_HZ: f64 = 1.0;
const BATTERY_IDLE_DRAIN: f64 = 0.02;
const BATTERY_MOTION_DRAIN: f64 = 0.5;
const BATTERY_MIN_VOLTAGE: f64 = 11.5;
const BATTERY_VOLTAGE_SPAN: f64 = 1.2;

#[derive(Default)]
struct SimState {
    x: f64,
    y: f64,
    theta: f64,
    linear: f64,
    angular: f64,
    left_wheel_angle: f64,
    right_wheel_angle: f64,
    battery_percent: f64,
}

impl SimState {
    fn new() -> Self {
        SimState {
            battery_percent: 100.0,
            ..Default::default()
        }
    }

    fn set_velocity_command(&mut self, linear: f64, angular: f64) {
        self.linear = linear;
        self.angular = angular;
    }

    fn stop(&mut self) {
        self.linear = 0.0;
        self.angular = 0.0;
    }

    fn integrate(&mut self, dt: f64) {
        (self.x, self.y, self.theta) =
            integrate_pose(self.x, self.y, self.theta, self.linear, self.angular, dt);
        let (left_speed, right_speed) = wheel_angular_velocities(self.linear, self.angular);
        self.left_wheel_angle += left_speed * dt;
        self.right_wheel_angle += right_speed * dt;
    }

    fn speed(&self) -> f64 {
        self.linear.abs() + self.angular.abs()
    }

    fn gps(&self, latitude_origin: f64, longitude_origin: f64) -> NavSatFix {
        let (sec, nanosec) = now_stamp();
        let (latitude, longitude) =
            enu_to_geodetic(self.x, self.y, latitude_origin, longitude_origin);
        let mut fix = NavSatFix::new().unwrap();
        fix.header.stamp.sec = sec;
        fix.header.stamp.nanosec = nanosec;
        fix.header.frame_id = RosString::new(BASE_LINK).unwrap();
        fix.status.status = NavSatStatus::STATUS_FIX;
        fix.status.service = NavSatStatus::SERVICE_GPS;
        fix.latitude = latitude;
        fix.longitude = longitude;
        fix.altitude = 0.0;
        fix.position_covariance = GPS_POSITION_COVARIANCE;
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
        let percentage_text = format!("{:.0}%", self.battery_percent);
        let battery = Status::new(
            battery_diagnostic_level(self.battery_percent),
            "battery",
            "simulator",
        )
        .message(&percentage_text)
        .value("percentage", &percentage_text);
        diagnostic_array(vec![battery])
    }
}

fn camera_messages(jpeg: Vec<u8>) -> (CompressedImage, CameraInfo) {
    let (sec, nanosec) = now_stamp();
    let (fx, fy, cx, cy) = camera_intrinsics(IMAGE_WIDTH, IMAGE_HEIGHT, CAMERA_FOV_DEG);

    let mut image = CompressedImage::new().unwrap();
    image.header.stamp.sec = sec;
    image.header.stamp.nanosec = nanosec;
    image.header.frame_id = RosString::new(CAMERA_OPTICAL).unwrap();
    image.format = RosString::new("jpeg").unwrap();
    image.data = jpeg.as_slice().try_into().unwrap();

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

pub async fn run_simulator(
    node: Arc<Node>,
    scene: Scene,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut cmd_vel = node.create_subscriber::<Twist>("cmd_vel", Some(qos::command()))?;
    let image_pub = node.create_publisher::<CompressedImage>(
        "camera/image_raw/compressed",
        Some(qos::sensor_data()),
    )?;
    let camera_info_pub = node
        .create_publisher::<CameraInfo>("camera/image_raw/camera_info", Some(qos::sensor_data()))?;
    let gps_pub = node.create_publisher::<NavSatFix>("gps/fix", Some(qos::sensor_data()))?;
    let battery_pub = node.create_publisher::<BatteryState>("battery", None)?;
    let diag_pub = node.create_publisher::<DiagnosticArray>("/diagnostics", None)?;
    let odom_pub = node.create_publisher::<Odometry>("odom", None)?;
    let joint_state_pub = node.create_publisher::<JointState>("joint_states", None)?;

    let mut param_server = node.create_parameter_server()?;
    {
        let mut params = param_server.params.write();
        let mut declare = |name: &str, value: Value, description: &str| {
            if params.get_parameter(name).is_none() {
                let _ = params.set_parameter(
                    name.to_string(),
                    value,
                    false,
                    Some(description.to_string()),
                );
            }
        };
        declare(
            "deadman_seconds",
            Value::F64(DEADMAN_SECONDS),
            "Halt the robot if no cmd_vel arrives within this many seconds",
        );
        declare(
            "latitude_origin",
            Value::F64(LATITUDE_ORIGIN),
            "GPS origin latitude in degrees",
        );
        declare(
            "longitude_origin",
            Value::F64(LONGITUDE_ORIGIN),
            "GPS origin longitude in degrees",
        );
        let _ = params.set_floating_point_range(
            "deadman_seconds",
            DEADMAN_MIN_SECONDS,
            DEADMAN_MAX_SECONDS,
            0.0,
        );
    }
    let params = param_server.params.clone();
    let read_f64 = |name: &str, fallback: f64| -> f64 {
        if let Some(parameter) = params.read().get_parameter(name) {
            if let Value::F64(value) = parameter.value {
                return value;
            }
            tracing::warn!("parameter '{name}' is not an f64; keeping {fallback}");
        }
        fallback
    };
    let mut deadman_seconds = read_f64("deadman_seconds", DEADMAN_SECONDS);
    let mut latitude_origin = read_f64("latitude_origin", LATITUDE_ORIGIN);
    let mut longitude_origin = read_f64("longitude_origin", LONGITUDE_ORIGIN);

    let camera_renderer = CameraRenderer::new(
        scene,
        IMAGE_WIDTH as u32,
        IMAGE_HEIGHT as u32,
        CAMERA_FOV_DEG,
        (placement::camera_origin().z - placement::ground_z()) * MM_TO_M,
    )
    .await?;
    let (pose_tx, pose_rx) = tokio::sync::watch::channel((0.0f64, 0.0f64, 0.0f64));
    let camera_task = tokio::spawn(async move {
        let mut camera_tick = interval(Duration::from_secs_f64(1.0 / CAMERA_HZ));
        let start = Instant::now();
        loop {
            camera_tick.tick().await;
            let (x, y, theta) = *pose_rx.borrow();
            let frame = camera_renderer.render(x, y, theta, start.elapsed().as_secs_f64());
            let mut jpeg = Vec::new();
            jpeg_encoder::Encoder::new(&mut jpeg, JPEG_QUALITY)
                .encode(
                    &frame,
                    IMAGE_WIDTH as u16,
                    IMAGE_HEIGHT as u16,
                    jpeg_encoder::ColorType::Rgba,
                )
                .ok();
            let (image, info) = camera_messages(jpeg);
            let _ = image_pub.send(&image);
            let _ = camera_info_pub.send(&info);
        }
    });

    let mut state = SimState::new();
    let mut last_command = Instant::now();
    let dt = 1.0 / PHYSICS_HZ;
    let mut physics_tick = interval(Duration::from_secs_f64(dt));
    let mut gps_tick = interval(Duration::from_secs_f64(1.0 / GPS_HZ));
    let mut battery_tick = interval(Duration::from_secs_f64(1.0 / BATTERY_HZ));
    let mut odom_tick = interval(Duration::from_secs_f64(1.0 / ODOMETRY_HZ));

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
                        latitude_origin = read_f64("latitude_origin", latitude_origin);
                        longitude_origin = read_f64("longitude_origin", longitude_origin);
                    }
                    Err(error) => tracing::warn!("parameter service error: {error}"),
                }
            }
            message = cmd_vel.recv() => {
                let twist = &message?.sample;
                state.set_velocity_command(twist.linear.x, twist.angular.z);
                last_command = Instant::now();
            }
            _ = physics_tick.tick() => {
                if command_is_stale(last_command.elapsed().as_secs_f64(), deadman_seconds) {
                    state.stop();
                }
                state.integrate(dt);
                let _ = pose_tx.send((state.x, state.y, state.theta));
            }
            _ = gps_tick.tick() => gps_pub.send(&state.gps(latitude_origin, longitude_origin))?,
            _ = odom_tick.tick() => {
                odom_pub.send(&state.odom())?;
                joint_state_pub.send(&joint_state_message(state.left_wheel_angle, state.right_wheel_angle))?;
            }
            _ = battery_tick.tick() => {
                battery_pub.send(&state.step_battery())?;
                diag_pub.send(&state.diagnostics())?;
            }
        }
    }

    tracing::info!("shutting down");
    camera_task.abort();
    Ok(())
}
