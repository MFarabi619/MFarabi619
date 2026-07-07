use std::sync::Arc;

use oxidros::{
    msg::{
        common_interfaces::sensor_msgs::msg::{CameraInfo, CompressedImage},
        msg::{F64Seq, RosString},
    },
    prelude::*,
};
use tokio::{io::AsyncReadExt, net::TcpStream};

use crate::{camera_intrinsics, frames::CAMERA_OPTICAL, now_stamp};

const SOI: [u8; 2] = [0xFF, 0xD8];
const EOI: [u8; 2] = [0xFF, 0xD9];
const READ_CHUNK: usize = 65536;
const IMAGE_WIDTH: usize = 1296;
const IMAGE_HEIGHT: usize = 972;
const CAMERA_FOV_DEG: f64 = 54.0;

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

fn camera_info(stamp: (i32, u32)) -> CameraInfo {
    let (fx, fy, cx, cy) = camera_intrinsics(IMAGE_WIDTH, IMAGE_HEIGHT, CAMERA_FOV_DEG);
    let mut info = CameraInfo::new().unwrap();
    info.header.stamp.sec = stamp.0;
    info.header.stamp.nanosec = stamp.1;
    info.header.frame_id = RosString::new(CAMERA_OPTICAL).unwrap();
    info.width = IMAGE_WIDTH as u32;
    info.height = IMAGE_HEIGHT as u32;
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
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let image_pub = node.create_publisher::<CompressedImage>(
        "camera/image_raw/compressed",
        Some(Profile::sensor_data()),
    )?;
    let info_pub = node.create_publisher::<CameraInfo>(
        "camera/image_raw/camera_info",
        Some(Profile::sensor_data()),
    )?;

    tracing::info!("streaming camera from {source} -> camera/image_raw/compressed");
    let mut stream = TcpStream::connect(&source).await?;
    stream.set_nodelay(true)?;
    let mut buffer = Vec::new();
    let mut chunk = vec![0u8; READ_CHUNK];
    loop {
        let read = stream.read(&mut chunk).await?;
        if read == 0 {
            break;
        }
        buffer.extend_from_slice(&chunk[..read]);
        while let Some(frame) = take_jpeg(&mut buffer) {
            let stamp = now_stamp();
            let _ = image_pub.send(&compressed_image(&frame, stamp));
            let _ = info_pub.send(&camera_info(stamp));
        }
    }

    tracing::warn!("camera stream at {source} closed");
    Ok(())
}
