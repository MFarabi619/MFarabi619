use std::{
    collections::{hash_map::Entry, HashMap},
    sync::Arc,
};

use oxidros::{
    msg::{common_interfaces::sensor_msgs::msg::CompressedImage, msg::RosString},
    prelude::*,
};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

pub struct WebcamSink {
    frames: tokio::sync::mpsc::UnboundedSender<(String, CompressedImage)>,
}

impl WebcamSink {
    pub fn accept(&self, topic: &str, encoding: &str, payload: &[u8]) {
        if let Some(image) = decode_compressed_image(encoding, payload) {
            let _ = self.frames.send((topic.to_string(), image));
        }
    }
}

pub fn spawn_webcam_forwarder(node: &Arc<Node>) -> Result<WebcamSink, BoxError> {
    let (frames, mut incoming) =
        tokio::sync::mpsc::unbounded_channel::<(String, CompressedImage)>();
    let node = node.clone();
    tokio::spawn(async move {
        let mut publishers: HashMap<String, Publisher<CompressedImage>> = HashMap::new();
        while let Some((topic, image)) = incoming.recv().await {
            let publisher = match publishers.entry(topic.clone()) {
                Entry::Occupied(existing) => existing.into_mut(),
                Entry::Vacant(slot) => {
                    match node.create_publisher::<CompressedImage>(
                        &topic,
                        Some(Profile::sensor_data()),
                    ) {
                        Ok(publisher) => {
                            tracing::info!(topic = %topic, "forwarding webcam frames");
                            slot.insert(publisher)
                        }
                        Err(error) => {
                            tracing::warn!("webcam publisher for {topic} failed: {error}");
                            continue;
                        }
                    }
                }
            };
            let _ = publisher.send(&image);
        }
    });
    Ok(WebcamSink { frames })
}

fn decode_compressed_image(encoding: &str, payload: &[u8]) -> Option<CompressedImage> {
    if encoding != "json" {
        return None;
    }
    let value: serde_json::Value = serde_json::from_slice(payload).ok()?;
    let bytes: Vec<u8> = value
        .get("data")?
        .get("data")?
        .as_array()?
        .iter()
        .map(|value| value.as_u64().unwrap_or(0) as u8)
        .collect();

    let mut image = CompressedImage::new()?;
    image.header.stamp.sec = value["timestamp"]["sec"].as_i64().unwrap_or(0) as i32;
    image.header.stamp.nanosec = value["timestamp"]["nsec"].as_u64().unwrap_or(0) as u32;
    image.header.frame_id = RosString::new(value["frame_id"].as_str().unwrap_or(""))?;
    image.format = RosString::new(value["format"].as_str().unwrap_or("jpeg"))?;
    image.data = bytes.as_slice().try_into().ok()?;
    Some(image)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_webcam_panel_json_into_ros_image() {
        let json = br#"{"timestamp":{"sec":1,"nsec":2},"frame_id":"cam","format":"jpeg","data":{"type":"Buffer","data":[255,216,255,217]}}"#;
        let image = decode_compressed_image("json", json).unwrap();
        assert_eq!(image.header.stamp.sec, 1);
        assert_eq!(image.header.stamp.nanosec, 2);
        assert_eq!(image.format.to_string(), "jpeg");
        assert_eq!(image.data.as_slice(), &[255, 216, 255, 217]);
    }

    #[test]
    fn rejects_non_json_encoding() {
        assert!(decode_compressed_image("cdr", b"\x00\x01\x02").is_none());
    }
}
