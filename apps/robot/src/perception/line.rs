use std::{
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Instant,
};

use foxglove::messages::{
    points_annotation, Color, ImageAnnotations, Point2, PointsAnnotation, TextAnnotation,
};
use oxidros::{
    msg::common_interfaces::{
        geometry_msgs::msg::Twist,
        sensor_msgs::msg::CompressedImage,
        std_srvs::srv::{SetBool, SetBool_Response},
    },
    prelude::*,
};

use super::{
    palm::{decode_rgb, RGB_CHANNELS},
    twist, WATCHDOG_TIMEOUT,
};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const LOG_STRIDE_FRAMES: u64 = 15;
const LABEL_SIZE: f64 = 24.0;
const FORWARD_SPEED: f64 = 0.4;
const STEERING_GAIN: f64 = 0.8;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LineColor {
    White,
    Yellow,
}

pub struct Config {
    // ROI band as fractions of the frame height — the road just ahead of the robot.
    pub roi_top: f64,
    pub roi_bottom: f64,
    // White = bright and unsaturated.
    pub white_max_saturation: f64,
    pub white_min_value: f64,
    // Yellow = a saturated hue band.
    pub yellow_hue_min: f64,
    pub yellow_hue_max: f64,
    pub yellow_min_saturation: f64,
    pub yellow_min_value: f64,
    // Fewer matched pixels than this reads as "no line" rather than noise.
    pub min_pixels: usize,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            roi_top: 0.55,
            roi_bottom: 1.0,
            white_max_saturation: 0.25,
            white_min_value: 0.65,
            yellow_hue_min: 35.0,
            yellow_hue_max: 70.0,
            yellow_min_saturation: 0.35,
            yellow_min_value: 0.45,
            min_pixels: 60,
        }
    }
}

#[derive(Clone, Copy, Default)]
pub struct BoundingBox {
    pub min_x: f64,
    pub min_y: f64,
    pub max_x: f64,
    pub max_y: f64,
}

pub struct LineDetection {
    pub found: bool,
    pub centroid_x: f64,
    pub centroid_y: f64,
    // Horizontal position of the line relative to frame center, normalized to [-1, 1]
    // (negative = line is left of center, positive = right). This is the steering error.
    pub offset: f64,
    pub bounding_box: BoundingBox,
    pub color: Option<LineColor>,
    pub pixel_count: usize,
}

impl LineDetection {
    fn none() -> Self {
        Self {
            found: false,
            centroid_x: 0.0,
            centroid_y: 0.0,
            offset: 0.0,
            bounding_box: BoundingBox::default(),
            color: None,
            pixel_count: 0,
        }
    }
}

pub(crate) fn rgb_to_hsv(red: u8, green: u8, blue: u8) -> (f64, f64, f64) {
    let red = red as f64 / 255.0;
    let green = green as f64 / 255.0;
    let blue = blue as f64 / 255.0;
    let max = red.max(green).max(blue);
    let min = red.min(green).min(blue);
    let delta = max - min;
    let hue = if delta == 0.0 {
        0.0
    } else if max == red {
        60.0 * (((green - blue) / delta).rem_euclid(6.0))
    } else if max == green {
        60.0 * ((blue - red) / delta + 2.0)
    } else {
        60.0 * ((red - green) / delta + 4.0)
    };
    let saturation = if max == 0.0 { 0.0 } else { delta / max };
    (hue, saturation, max)
}

fn classify(hue: f64, saturation: f64, value: f64, config: &Config) -> Option<LineColor> {
    if saturation <= config.white_max_saturation && value >= config.white_min_value {
        Some(LineColor::White)
    } else if hue >= config.yellow_hue_min
        && hue <= config.yellow_hue_max
        && saturation >= config.yellow_min_saturation
        && value >= config.yellow_min_value
    {
        Some(LineColor::Yellow)
    } else {
        None
    }
}

pub fn detect(
    config: &Config,
    target_color: LineColor,
    rgb: &[u8],
    width: usize,
    height: usize,
) -> LineDetection {
    let row_start = (config.roi_top * height as f64) as usize;
    let row_end = ((config.roi_bottom * height as f64) as usize).min(height);

    let (mut sum_x, mut sum_y, mut count) = (0.0, 0.0, 0usize);
    let mut bounding = BoundingBox {
        min_x: width as f64,
        min_y: height as f64,
        max_x: 0.0,
        max_y: 0.0,
    };

    for y in row_start..row_end {
        for x in 0..width {
            let pixel = (y * width + x) * RGB_CHANNELS;
            let (hue, saturation, value) = rgb_to_hsv(rgb[pixel], rgb[pixel + 1], rgb[pixel + 2]);
            if classify(hue, saturation, value, config) != Some(target_color) {
                continue;
            }
            let (x, y) = (x as f64, y as f64);
            sum_x += x;
            sum_y += y;
            count += 1;
            bounding.min_x = bounding.min_x.min(x);
            bounding.min_y = bounding.min_y.min(y);
            bounding.max_x = bounding.max_x.max(x);
            bounding.max_y = bounding.max_y.max(y);
        }
    }

    if count < config.min_pixels {
        return LineDetection::none();
    }
    let centroid_x = sum_x / count as f64;
    let half_width = width as f64 / 2.0;
    LineDetection {
        found: true,
        centroid_x,
        centroid_y: sum_y / count as f64,
        offset: (centroid_x - half_width) / half_width,
        bounding_box: bounding,
        color: Some(target_color),
        pixel_count: count,
    }
}

pub(crate) fn color(r: f32, g: f32, b: f32, a: f32) -> Color {
    Color {
        r: r as f64,
        g: g as f64,
        b: b as f64,
        a: a as f64,
    }
}

fn point(x: f64, y: f64) -> Point2 {
    Point2 { x, y }
}

pub(crate) fn box_outline(
    bounding: &BoundingBox,
    outline: Color,
    thickness: f64,
) -> PointsAnnotation {
    PointsAnnotation {
        r#type: points_annotation::Type::LineLoop as i32,
        points: vec![
            point(bounding.min_x, bounding.min_y),
            point(bounding.max_x, bounding.min_y),
            point(bounding.max_x, bounding.max_y),
            point(bounding.min_x, bounding.max_y),
        ],
        outline_color: Some(outline),
        thickness,
        ..Default::default()
    }
}

pub(crate) fn label(text: String, x: f64, y: f64, text_color: Color) -> TextAnnotation {
    TextAnnotation {
        position: Some(point(x.max(0.0), y.max(LABEL_SIZE))),
        text,
        font_size: LABEL_SIZE,
        text_color: Some(text_color),
        background_color: Some(color(0.0, 0.0, 0.0, 0.6)),
        ..Default::default()
    }
}

fn overlay(
    detection: &LineDetection,
    config: &Config,
    width: usize,
    height: usize,
) -> ImageAnnotations {
    let mut annotations = ImageAnnotations::default();
    let roi = BoundingBox {
        min_x: 0.0,
        min_y: config.roi_top * height as f64,
        max_x: width as f64 - 1.0,
        max_y: config.roi_bottom * height as f64 - 1.0,
    };
    annotations
        .points
        .push(box_outline(&roi, color(0.5, 0.5, 0.5, 0.8), 1.0));

    if detection.found {
        let line_color = color(0.1, 1.0, 0.3, 1.0);
        annotations
            .points
            .push(box_outline(&detection.bounding_box, line_color, 2.0));
        annotations.points.push(PointsAnnotation {
            r#type: points_annotation::Type::Points as i32,
            points: vec![point(detection.centroid_x, detection.centroid_y)],
            outline_color: Some(line_color),
            thickness: 8.0,
            ..Default::default()
        });
        // Steering vector: frame-center bottom -> detected line centroid.
        annotations.points.push(PointsAnnotation {
            r#type: points_annotation::Type::LineList as i32,
            points: vec![
                point(width as f64 / 2.0, height as f64 - 1.0),
                point(detection.centroid_x, detection.centroid_y),
            ],
            outline_color: Some(color(0.2, 0.8, 1.0, 1.0)),
            thickness: 2.0,
            ..Default::default()
        });
        let color_label = detection
            .color
            .map(|c| format!("{c:?}"))
            .unwrap_or_default();
        annotations.texts.push(label(
            format!("{color_label}  offset {:+.2}", detection.offset),
            detection.bounding_box.min_x,
            detection.bounding_box.min_y - LABEL_SIZE,
            line_color,
        ));
    } else {
        annotations.texts.push(label(
            "no line".to_string(),
            width as f64 / 2.0 - 40.0,
            roi.min_y,
            color(0.7, 0.7, 0.7, 1.0),
        ));
    }
    annotations
}

fn follow(detection: &LineDetection) -> Twist {
    if detection.found {
        twist(FORWARD_SPEED, -STEERING_GAIN * detection.offset)
    } else {
        twist(0.0, 0.0)
    }
}

pub async fn run_line_follower(node: Arc<Node>, target_color: LineColor) -> Result<(), BoxError> {
    let config = Config::default();
    let mut images = node.create_subscriber::<CompressedImage>(
        "camera/image_raw/compressed",
        Some(crate::qos::sensor_data()),
    )?;
    let cmd_vel = node.create_publisher::<Twist>("cmd_vel", Some(crate::qos::command()))?;
    let mut enable = node.create_server::<SetBool>("line_follower/enable", None)?;
    let overlay_channel =
        foxglove::ChannelBuilder::new("/line/overlay").build::<ImageAnnotations>();
    let frames = AtomicU64::new(0);
    let mut enabled = true;

    tracing::info!("line follower on camera/image_raw/compressed -> cmd_vel + /line/overlay");
    let ctrl_c = tokio::signal::ctrl_c();
    tokio::pin!(ctrl_c);
    let mut watchdog = tokio::time::interval(WATCHDOG_TIMEOUT);
    let mut last_frame = Instant::now();
    loop {
        tokio::select! {
            _ = &mut ctrl_c => break,
            request = enable.recv() => {
                let request = request?;
                enabled = request.request().data;
                if !enabled {
                    let _ = cmd_vel.send(&twist(0.0, 0.0));
                }
                let mut response = SetBool_Response::new().unwrap();
                response.success = true;
                let _ = request.respond(&response);
                tracing::info!("autonomy {}", if enabled { "enabled" } else { "disabled" });
            }
            _ = watchdog.tick() => {
                if last_frame.elapsed() >= WATCHDOG_TIMEOUT {
                    overlay_channel.log(&ImageAnnotations::default());
                    let _ = cmd_vel.send(&twist(0.0, 0.0));
                }
            }
            message = images.recv() => {
                last_frame = Instant::now();
                match decode_rgb(message?.sample.data.as_slice()) {
                    Err(error) => tracing::warn!("{error}"),
                    Ok((rgb, width, height)) => {
                        let detection = detect(&config, target_color, &rgb, width, height);
                        overlay_channel.log(&overlay(&detection, &config, width, height));
                        let velocity = if enabled { follow(&detection) } else { twist(0.0, 0.0) };
                        cmd_vel.send(&velocity)?;
                        if frames.fetch_add(1, Ordering::Relaxed).is_multiple_of(LOG_STRIDE_FRAMES) {
                            match detection.color {
                                Some(color) => tracing::info!(
                                    "line {color:?} offset {:+.2} ({} px)",
                                    detection.offset,
                                    detection.pixel_count
                                ),
                                None => tracing::info!("no line"),
                            }
                        }
                    }
                }
            }
        }
    }

    let _ = cmd_vel.send(&twist(0.0, 0.0));
    tracing::info!("line follower stopping");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame_with_stripe(width: usize, height: usize, stripe: std::ops::Range<usize>) -> Vec<u8> {
        let mut rgb = vec![0u8; width * height * RGB_CHANNELS];
        for y in 0..height {
            for x in stripe.clone() {
                let pixel = (y * width + x) * RGB_CHANNELS;
                rgb[pixel] = 255;
                rgb[pixel + 1] = 255;
                rgb[pixel + 2] = 255;
            }
        }
        rgb
    }

    #[test]
    fn white_is_bright_and_unsaturated() {
        let (_, saturation, value) = rgb_to_hsv(255, 255, 255);
        assert_eq!(saturation, 0.0);
        assert_eq!(value, 1.0);
    }

    #[test]
    fn yellow_lands_in_the_hue_band() {
        let (hue, saturation, value) = rgb_to_hsv(255, 255, 0);
        assert_eq!(hue, 60.0);
        assert_eq!(saturation, 1.0);
        assert_eq!(value, 1.0);
    }

    #[test]
    fn centered_line_has_near_zero_offset() {
        let (width, height) = (100, 100);
        let rgb = frame_with_stripe(width, height, 45..55);
        let detection = detect(&Config::default(), LineColor::White, &rgb, width, height);
        assert!(detection.found);
        assert!(detection.offset.abs() < 0.05, "offset {}", detection.offset);
    }

    #[test]
    fn line_to_the_right_gives_positive_offset() {
        let (width, height) = (100, 100);
        let rgb = frame_with_stripe(width, height, 80..90);
        let detection = detect(&Config::default(), LineColor::White, &rgb, width, height);
        assert!(detection.found);
        assert!(detection.offset > 0.3, "offset {}", detection.offset);
    }

    #[test]
    fn an_empty_frame_finds_no_line() {
        let (width, height) = (100, 100);
        let rgb = vec![0u8; width * height * RGB_CHANNELS];
        let detection = detect(&Config::default(), LineColor::White, &rgb, width, height);
        assert!(!detection.found);
    }
}
