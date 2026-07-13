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
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
};

use crate::{frames::CAMERA_OPTICAL, now_stamp, qos};

const SOI: [u8; 2] = [0xFF, 0xD8];
const EOI: [u8; 2] = [0xFF, 0xD9];
const READ_CHUNK: usize = 65536;
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

fn compressed_image(jpeg: &[u8], stamp: (i32, u32)) -> CompressedImage {
    let mut image = CompressedImage::new().unwrap();
    image.header.stamp.sec = stamp.0;
    image.header.stamp.nanosec = stamp.1;
    image.header.frame_id = RosString::new(CAMERA_OPTICAL).unwrap();
    image.format = RosString::new("jpeg").unwrap();
    image.data = jpeg.try_into().unwrap();
    image
}

fn camera_info(profile: CameraProfile, stamp: (i32, u32)) -> CameraInfo {
    let (fx, fy, cx, cy) = camera_intrinsics(profile.width, profile.height, profile.fov_deg);
    let mut info = CameraInfo::new().unwrap();
    info.header.stamp.sec = stamp.0;
    info.header.stamp.nanosec = stamp.1;
    info.header.frame_id = RosString::new(CAMERA_OPTICAL).unwrap();
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
    source: String,
    profile: CameraProfile,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let image_pub = node.create_publisher::<CompressedImage>(
        "camera/image_raw/compressed",
        Some(qos::sensor_data()),
    )?;
    let info_pub = node
        .create_publisher::<CameraInfo>("camera/image_raw/camera_info", Some(qos::sensor_data()))?;

    tracing::info!("streaming camera from {source} -> camera/image_raw/compressed");
    let mut stream = TcpStream::connect(&source).await?;
    stream.set_nodelay(true)?;
    let request = format!("GET {STREAM_PATH} HTTP/1.0\r\nHost: {source}\r\n\r\n");
    stream.write_all(request.as_bytes()).await?;
    let mut buffer = Vec::new();
    let mut chunk = vec![0u8; READ_CHUNK];
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
            let _ = image_pub.send(&compressed_image(&frame, stamp));
            let _ = info_pub.send(&camera_info(profile, stamp));
        }
    }

    tracing::warn!("camera stream at {source} closed");
    Ok(())
}

pub fn camera_intrinsics(width: usize, height: usize, fov_deg: f64) -> (f64, f64, f64, f64) {
    let focal = (width as f64 / 2.0) / (fov_deg.to_radians() / 2.0).tan();
    (focal, focal, width as f64 / 2.0, height as f64 / 2.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn camera_intrinsics_center_is_half_the_frame() {
        let (_, _, cx, cy) = camera_intrinsics(640, 400, 70.0);
        assert_eq!(cx, 320.0);
        assert_eq!(cy, 200.0);
    }
}
