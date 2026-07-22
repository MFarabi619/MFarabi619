use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use oxidros::{
    msg::{
        common_interfaces::sensor_msgs::msg::{CameraInfo, CompressedImage},
        msg::{F64Seq, RosString},
    },
    prelude::*,
};
use robot_control::params::{f64_param, string_param};
use robot_description::{camera_intrinsics, time::now_stamp};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
};

const SOI: [u8; 2] = [0xFF, 0xD8];
const EOI: [u8; 2] = [0xFF, 0xD9];
const READ_CHUNK_BYTES: usize = 65536;

#[derive(Clone, Copy)]
pub struct CameraProfile {
    pub width: usize,
    pub height: usize,
    pub fov_deg: f64,
}

pub const IMX296_GS: CameraProfile = CameraProfile {
    width: 1456,
    height: 1088,
    fov_deg: 54.0,
};
pub const USB_WEBCAM: CameraProfile = CameraProfile {
    width: 1920,
    height: 1200,
    fov_deg: 54.0,
};
pub const ORBBEC_GEMINI_335L: CameraProfile = CameraProfile {
    width: 1280,
    height: 720,
    fov_deg: 90.0,
};
const STREAM_PATH: &str = "/stream";
const PUBLISH_INTERVAL: Duration = Duration::from_millis(50);

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

fn take_jpeg(buffer: &mut Vec<u8>) -> Option<Vec<u8>> {
    let start = find(buffer.as_slice(), &SOI)?;
    let end = start + 2 + find(&buffer[start + 2..], &EOI)? + 2;
    let frame = buffer[start..end].to_vec();
    buffer.drain(..end);
    Some(frame)
}

fn compressed_image(jpeg: &[u8], frame_id: &str, (sec, nanosec): (i32, u32)) -> CompressedImage {
    let mut image = CompressedImage::new().unwrap();
    image.header.stamp.sec = sec;
    image.header.stamp.nanosec = nanosec;
    image.header.frame_id = RosString::new(frame_id).unwrap();
    image.format = RosString::new("jpeg").unwrap();
    image.data = jpeg.try_into().unwrap();
    image
}

fn camera_info(profile: CameraProfile, frame_id: &str, (sec, nanosec): (i32, u32)) -> CameraInfo {
    let (fx, fy, cx, cy) = camera_intrinsics(profile.width, profile.height, profile.fov_deg);
    let mut info = CameraInfo::new().unwrap();
    info.header.stamp.sec = sec;
    info.header.stamp.nanosec = nanosec;
    info.header.frame_id = RosString::new(frame_id).unwrap();
    info.width = profile.width as u32;
    info.height = profile.height as u32;
    info.distortion_model = RosString::new("plumb_bob").unwrap();
    info.d = F64Seq::new(5).unwrap();
    info.k = [fx, 0.0, cx, 0.0, fy, cy, 0.0, 0.0, 1.0];
    info.r = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
    info.p = [fx, 0.0, cx, 0.0, 0.0, fy, cy, 0.0, 0.0, 0.0, 1.0, 0.0];
    info
}

pub async fn run_camera(
    node: Arc<Node>,
    default_host: String,
    default_port: u16,
    profile: CameraProfile,
) -> Result<(), crate::BoxError> {
    let (source, image_topic, info_topic, frame_id) = {
        let parameters = node.create_parameter_server()?;
        let store = parameters.params.read();
        let name = string_param(&store, "name", "camera_0");
        let host = string_param(&store, "host", &default_host);
        let port = f64_param(&store, "port", default_port as f64) as u16;
        (
            format!("{host}:{port}"),
            format!("sensors/{name}/color/image/compressed"),
            format!("sensors/{name}/color/camera_info"),
            format!("{name}_color_optical_frame"),
        )
    };
    let image_pub =
        node.create_publisher::<CompressedImage>(&image_topic, Some(Profile::sensor_data()))?;
    let info_pub =
        node.create_publisher::<CameraInfo>(&info_topic, Some(Profile::sensor_data()))?;

    tracing::info!("streaming camera from {source} -> {image_topic}");
    let mut stream = TcpStream::connect(&source).await?;
    stream.set_nodelay(true)?;
    let request = format!("GET {STREAM_PATH} HTTP/1.0\r\nHost: {source}\r\n\r\n");
    stream.write_all(request.as_bytes()).await?;
    let mut buffer = Vec::new();
    let mut chunk = vec![0u8; READ_CHUNK_BYTES];
    let mut last_publish: Option<Instant> = None;
    loop {
        let read = stream.read(&mut chunk).await?;
        if read == 0 {
            break;
        }
        buffer.extend_from_slice(&chunk[..read]);
        while let Some(frame) = take_jpeg(&mut buffer) {
            if last_publish.is_some_and(|previous| previous.elapsed() < PUBLISH_INTERVAL) {
                continue;
            }
            last_publish = Some(Instant::now());
            let stamp = now_stamp();
            let _ = image_pub.send(&compressed_image(&frame, &frame_id, stamp));
            let _ = info_pub.send(&camera_info(profile, &frame_id, stamp));
        }
    }

    tracing::warn!("camera stream at {source} closed");
    Ok(())
}
