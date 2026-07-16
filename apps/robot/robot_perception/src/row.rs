use std::{
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Instant,
};

use foxglove::messages::{points_annotation, ImageAnnotations, PointsAnnotation};
use oxidros::{
    msg::common_interfaces::{
        geometry_msgs::msg::TwistStamped,
        sensor_msgs::msg::CompressedImage,
        std_srvs::srv::{SetBool, SetBool_Response},
    },
    prelude::*,
};

use super::{
    line::{box_outline, color, label, point, rgb_to_hsv, BoundingBox},
    palm::{decode_rgb, RGB_CHANNELS},
    twist, WATCHDOG_TIMEOUT,
};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const LOG_STRIDE_FRAMES: u64 = 15;
const LABEL_OFFSET: f64 = 24.0;
const DEFAULT_FORWARD_SPEED: f64 = 0.4;
const DEFAULT_STEERING_GAIN: f64 = 0.8;

pub struct Config {
    // ROI band as fractions of the frame height — the ground just ahead of the robot.
    pub roi_top: f64,
    pub roi_bottom: f64,
    // A crop pixel is chromatic and sits in the green or the red/burgundy hue band; bare
    // soil is orange-tan and drops out of both, so plain green-excess would miss the red rows.
    pub min_saturation: f64,
    pub min_value: f64,
    pub green_hue_min: f64,
    pub green_hue_max: f64,
    pub red_hue_min: f64,
    pub red_hue_max: f64,
    // A column whose crop fraction rises above this reads as a crop row to straddle; the robot
    // centers the row so the bed passes under it and the wheels ride the aisles either side.
    pub crop_min_fraction: f64,
    // Narrower bands than this fraction of the frame width are noise, not a row.
    pub min_row_width: f64,
    pub smooth_window: usize,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            roi_top: 0.5,
            roi_bottom: 1.0,
            min_saturation: 0.30,
            min_value: 0.06,
            green_hue_min: 70.0,
            green_hue_max: 175.0,
            red_hue_min: 315.0,
            red_hue_max: 18.0,
            crop_min_fraction: 0.40,
            min_row_width: 0.04,
            smooth_window: 9,
        }
    }
}

pub struct RowDetection {
    pub found: bool,
    pub row_center_x: f64,
    // Horizontal position of the crop row relative to frame center, normalized to [-1, 1]
    // (negative = row is left of center, positive = right). This is the steering error.
    pub offset: f64,
    pub band: BoundingBox,
    pub vegetation: f64,
}

impl RowDetection {
    fn none() -> Self {
        Self {
            found: false,
            row_center_x: 0.0,
            offset: 0.0,
            band: BoundingBox::default(),
            vegetation: 0.0,
        }
    }
}

fn is_crop(hue: f64, saturation: f64, value: f64, config: &Config) -> bool {
    if saturation < config.min_saturation || value < config.min_value {
        return false;
    }
    let green = hue >= config.green_hue_min && hue <= config.green_hue_max;
    let red = hue >= config.red_hue_min || hue <= config.red_hue_max;
    green || red
}

fn smooth(profile: &[f64], window: usize) -> Vec<f64> {
    if window <= 1 {
        return profile.to_vec();
    }
    let half = window / 2;
    (0..profile.len())
        .map(|center| {
            let low = center.saturating_sub(half);
            let high = (center + half + 1).min(profile.len());
            profile[low..high].iter().sum::<f64>() / (high - low) as f64
        })
        .collect()
}

fn nearer_to_center(
    best: Option<(usize, usize)>,
    run: (usize, usize),
    center: f64,
) -> Option<(usize, usize)> {
    let run_center = (run.0 + run.1) as f64 / 2.0;
    match best {
        Some(kept) if ((kept.0 + kept.1) as f64 / 2.0 - center).abs() <= (run_center - center).abs() => {
            Some(kept)
        }
        _ => Some(run),
    }
}

pub fn detect(config: &Config, rgb: &[u8], width: usize, height: usize) -> RowDetection {
    let row_start = (config.roi_top * height as f64) as usize;
    let row_end = ((config.roi_bottom * height as f64) as usize).min(height);
    let roi_rows = row_end.saturating_sub(row_start);
    if roi_rows == 0 || width == 0 {
        return RowDetection::none();
    }

    let mut crop_columns = vec![0u32; width];
    for y in row_start..row_end {
        for (x, count) in crop_columns.iter_mut().enumerate() {
            let pixel = (y * width + x) * RGB_CHANNELS;
            let (hue, saturation, value) = rgb_to_hsv(rgb[pixel], rgb[pixel + 1], rgb[pixel + 2]);
            if is_crop(hue, saturation, value, config) {
                *count += 1;
            }
        }
    }

    let fraction: Vec<f64> = crop_columns
        .iter()
        .map(|&count| count as f64 / roi_rows as f64)
        .collect();
    let smoothed = smooth(&fraction, config.smooth_window);

    let min_run = ((config.min_row_width * width as f64) as usize).max(1);
    let center = width as f64 / 2.0;
    let mut best: Option<(usize, usize)> = None;
    let mut run_start: Option<usize> = None;
    for x in 0..=width {
        let is_row = smoothed
            .get(x)
            .is_some_and(|&fraction| fraction >= config.crop_min_fraction);
        if is_row {
            run_start.get_or_insert(x);
        } else if let Some(start) = run_start.take() {
            if x - start >= min_run {
                best = nearer_to_center(best, (start, x), center);
            }
        }
    }

    let vegetation = fraction.iter().sum::<f64>() / width as f64;
    match best {
        None => RowDetection::none(),
        Some((start, end)) => {
            let row_center_x = (start + end) as f64 / 2.0;
            RowDetection {
                found: true,
                row_center_x,
                offset: (row_center_x - center) / center,
                band: BoundingBox {
                    min_x: start as f64,
                    min_y: row_start as f64,
                    max_x: (end - 1) as f64,
                    max_y: (row_end - 1) as f64,
                },
                vegetation,
            }
        }
    }
}

fn overlay(
    detection: &RowDetection,
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
        let marker = color(0.2, 0.9, 1.0, 1.0);
        annotations
            .points
            .push(box_outline(&detection.band, color(0.3, 1.0, 0.4, 1.0), 2.0));
        annotations.points.push(PointsAnnotation {
            r#type: points_annotation::Type::LineList as i32,
            points: vec![
                point(width as f64 / 2.0, height as f64 - 1.0),
                point(detection.row_center_x, (roi.min_y + roi.max_y) / 2.0),
            ],
            outline_color: Some(marker),
            thickness: 3.0,
            ..Default::default()
        });
        annotations.texts.push(label(
            format!("row offset {:+.2}", detection.offset),
            detection.band.min_x,
            detection.band.min_y - LABEL_OFFSET,
            marker,
        ));
    } else {
        annotations.texts.push(label(
            "no row".to_string(),
            width as f64 / 2.0 - 40.0,
            roi.min_y,
            color(0.7, 0.7, 0.7, 1.0),
        ));
    }
    annotations
}

fn follow(detection: &RowDetection, forward_speed: f64, steering_gain: f64) -> TwistStamped {
    if detection.found {
        twist(forward_speed, -steering_gain * detection.offset)
    } else {
        twist(0.0, 0.0)
    }
}

pub async fn run_row_follower(node: Arc<Node>, start_enabled: bool) -> Result<(), BoxError> {
    let config = Config::default();
    let (image_topic, forward_speed, steering_gain) = {
        let params = node.create_parameter_server()?;
        let store = params.params.read();
        (
            crate::params::string_param(&store, "image_topic", crate::params::DEFAULT_IMAGE_TOPIC),
            crate::params::f64_param(&store, "forward_speed", DEFAULT_FORWARD_SPEED),
            crate::params::f64_param(&store, "steering_gain", DEFAULT_STEERING_GAIN),
        )
    };
    let mut images = node
        .create_subscriber::<CompressedImage>(&image_topic, Some(Profile::sensor_data()))?;
    let cmd_vel = node.create_publisher::<TwistStamped>("cmd_vel_autonomy", Some(Profile { depth: 1, ..Profile::sensor_data() }))?;
    let mut enable = node.create_server::<SetBool>("~/enable", None)?;
    let overlay_channel = foxglove::ChannelBuilder::new("/row/overlay").build::<ImageAnnotations>();
    let frames = AtomicU64::new(0);
    let mut enabled = start_enabled;

    tracing::info!(
        "row follower on {} -> cmd_vel + /row/overlay (forward {forward_speed} m/s)",
        images.fully_qualified_topic_name()
    );
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
                    if enabled {
                        let _ = cmd_vel.send(&twist(0.0, 0.0));
                    }
                }
            }
            message = images.recv() => {
                last_frame = Instant::now();
                match decode_rgb(message?.sample.data.as_slice()) {
                    Err(error) => tracing::warn!("{error}"),
                    Ok((rgb, width, height)) => {
                        let detection = detect(&config, &rgb, width, height);
                        overlay_channel.log(&overlay(&detection, &config, width, height));
                        if enabled {
                            cmd_vel.send(&follow(&detection, forward_speed, steering_gain))?;
                        }
                        if frames.fetch_add(1, Ordering::Relaxed).is_multiple_of(LOG_STRIDE_FRAMES) {
                            if detection.found {
                                tracing::info!(
                                    "row offset {:+.2} (vegetation {:.0}%)",
                                    detection.offset,
                                    detection.vegetation * 100.0
                                );
                            } else {
                                tracing::info!("no row (vegetation {:.0}%)", detection.vegetation * 100.0);
                            }
                        }
                    }
                }
            }
        }
    }

    let _ = cmd_vel.send(&twist(0.0, 0.0));
    tracing::info!("row follower stopping");
    Ok(())
}

#[cfg(test)]
#[allow(clippy::single_range_in_vec_init)]
mod tests {
    use super::*;

    fn frame(width: usize, height: usize, crops: &[std::ops::Range<usize>]) -> Vec<u8> {
        let mut rgb = vec![0u8; width * height * RGB_CHANNELS];
        for y in 0..height {
            for x in 0..width {
                let pixel = (y * width + x) * RGB_CHANNELS;
                let planted = crops.iter().any(|crop| crop.contains(&x));
                let (r, g, b) = if planted { (80, 150, 40) } else { (180, 150, 110) };
                rgb[pixel] = r;
                rgb[pixel + 1] = g;
                rgb[pixel + 2] = b;
            }
        }
        rgb
    }

    #[test]
    fn green_is_crop_tan_is_ground() {
        let config = Config::default();
        let (green_hue, green_sat, green_val) = rgb_to_hsv(80, 150, 40);
        let (tan_hue, tan_sat, tan_val) = rgb_to_hsv(180, 150, 110);
        assert!(is_crop(green_hue, green_sat, green_val, &config));
        assert!(!is_crop(tan_hue, tan_sat, tan_val, &config));
    }

    #[test]
    fn burgundy_counts_as_crop() {
        let config = Config::default();
        let (hue, saturation, value) = rgb_to_hsv(90, 24, 30);
        assert!(is_crop(hue, saturation, value, &config));
    }

    #[test]
    fn centered_row_has_near_zero_offset() {
        let (width, height) = (120, 80);
        let rgb = frame(width, height, &[45..75]);
        let detection = detect(&Config::default(), &rgb, width, height);
        assert!(detection.found);
        assert!(detection.offset.abs() < 0.05, "offset {}", detection.offset);
    }

    #[test]
    fn row_to_the_right_gives_positive_offset() {
        let (width, height) = (120, 80);
        let rgb = frame(width, height, &[85..115]);
        let detection = detect(&Config::default(), &rgb, width, height);
        assert!(detection.found);
        assert!(detection.offset > 0.3, "offset {}", detection.offset);
    }

    #[test]
    fn picks_the_row_nearest_center() {
        let (width, height) = (120, 80);
        let rgb = frame(width, height, &[10..30, 55..85]);
        let detection = detect(&Config::default(), &rgb, width, height);
        assert!(detection.found);
        assert!(detection.offset > 0.0 && detection.offset < 0.3, "offset {}", detection.offset);
    }

    #[test]
    fn bare_ground_finds_no_row() {
        let (width, height) = (120, 80);
        let rgb = frame(width, height, &[]);
        let detection = detect(&Config::default(), &rgb, width, height);
        assert!(!detection.found);
    }
}
