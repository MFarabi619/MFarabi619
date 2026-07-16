// "Drive forward until you reach the grass." Grass green is vivid and saturated, so a simple hue
// mask is robust. We measure how much of the near-field band (just ahead of the robot) is green and
// stop once it fills past a threshold — the grass boundary has come down the frame to the robot.
use std::{
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Instant,
};

use foxglove::messages::ImageAnnotations;
use oxidros::{
    msg::common_interfaces::{geometry_msgs::msg::TwistStamped, sensor_msgs::msg::CompressedImage},
    prelude::*,
};

use super::{
    line::{box_outline, color, label, rgb_to_hsv, BoundingBox},
    palm::{decode_rgb, RGB_CHANNELS},
    twist, WATCHDOG_TIMEOUT,
};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const LOG_STRIDE_FRAMES: u64 = 15;
const LABEL_SIZE: f64 = 28.0;
// Normalized forward command while approaching — deliberately gentle.
const FORWARD_SPEED: f64 = 0.35;

pub struct Config {
    pub hue_min: f64,
    pub hue_max: f64,
    pub min_saturation: f64,
    pub min_value: f64,
    // The near-field band as a fraction of the frame height — the ground right in front of the robot.
    pub near_roi_top: f64,
    // Fraction of that band that must be green to count as "reached".
    pub coverage_threshold: f64,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            hue_min: 70.0,
            hue_max: 165.0,
            min_saturation: 0.25,
            min_value: 0.20,
            near_roi_top: 0.75,
            coverage_threshold: 0.30,
        }
    }
}

pub struct GreenGate {
    pub coverage: f64,
    pub reached: bool,
}

fn is_green(hue: f64, saturation: f64, value: f64, config: &Config) -> bool {
    hue >= config.hue_min
        && hue <= config.hue_max
        && saturation >= config.min_saturation
        && value >= config.min_value
}

pub fn detect_green(config: &Config, rgb: &[u8], width: usize, height: usize) -> GreenGate {
    let row_start = (config.near_roi_top * height as f64) as usize;
    let total = ((height - row_start) * width).max(1);
    let mut green = 0usize;
    for y in row_start..height {
        for x in 0..width {
            let pixel = (y * width + x) * RGB_CHANNELS;
            let (hue, saturation, value) = rgb_to_hsv(rgb[pixel], rgb[pixel + 1], rgb[pixel + 2]);
            if is_green(hue, saturation, value, config) {
                green += 1;
            }
        }
    }
    let coverage = green as f64 / total as f64;
    GreenGate {
        coverage,
        reached: coverage >= config.coverage_threshold,
    }
}

fn overlay(gate: &GreenGate, config: &Config, width: usize, height: usize) -> ImageAnnotations {
    let mut annotations = ImageAnnotations::default();
    let band = BoundingBox {
        min_x: 0.0,
        min_y: config.near_roi_top * height as f64,
        max_x: width as f64 - 1.0,
        max_y: height as f64 - 1.0,
    };
    let status_color = if gate.reached {
        color(0.1, 1.0, 0.3, 1.0)
    } else {
        color(0.9, 0.7, 0.1, 1.0)
    };
    annotations
        .points
        .push(box_outline(&band, status_color, 3.0));
    let text = if gate.reached {
        format!("REACHED  green {:.0}%", gate.coverage * 100.0)
    } else {
        format!("approaching  green {:.0}%", gate.coverage * 100.0)
    };
    annotations
        .texts
        .push(label(text, 8.0, band.min_y - LABEL_SIZE, status_color));
    annotations
}

pub async fn run_green_approach(node: Arc<Node>) -> Result<(), BoxError> {
    let config = Config::default();
    let mut images = node.create_subscriber::<CompressedImage>(
        "camera/image_raw/compressed",
        Some(Profile::sensor_data()),
    )?;
    let cmd_vel = node.create_publisher::<TwistStamped>("cmd_vel_autonomy", Some(Profile { depth: 1, ..Profile::sensor_data() }))?;
    let overlay_channel =
        foxglove::ChannelBuilder::new("/green/overlay").build::<ImageAnnotations>();
    let frames = AtomicU64::new(0);

    tracing::info!("green approach: driving forward on camera/image_raw/compressed until grass");
    let ctrl_c = tokio::signal::ctrl_c();
    tokio::pin!(ctrl_c);
    let mut watchdog = tokio::time::interval(WATCHDOG_TIMEOUT);
    let mut last_frame = Instant::now();
    loop {
        tokio::select! {
            _ = &mut ctrl_c => break,
            _ = watchdog.tick() => {
                // No frames: stop and clear the overlay (the driver deadman is the backstop).
                if last_frame.elapsed() >= WATCHDOG_TIMEOUT {
                    let _ = cmd_vel.send(&twist(0.0, 0.0));
                    overlay_channel.log(&ImageAnnotations::default());
                }
            }
            message = images.recv() => {
                last_frame = Instant::now();
                match decode_rgb(message?.sample.data.as_slice()) {
                    Err(error) => tracing::warn!("{error}"),
                    Ok((rgb, width, height)) => {
                        let gate = detect_green(&config, &rgb, width, height);
                        let forward = if gate.reached { 0.0 } else { FORWARD_SPEED };
                        cmd_vel.send(&twist(forward, 0.0))?;
                        overlay_channel.log(&overlay(&gate, &config, width, height));
                        if frames.fetch_add(1, Ordering::Relaxed).is_multiple_of(LOG_STRIDE_FRAMES) {
                            tracing::info!(
                                "green {:.0}% {}",
                                gate.coverage * 100.0,
                                if gate.reached { "REACHED (stop)" } else { "approaching" }
                            );
                        }
                    }
                }
            }
        }
    }

    tracing::info!("green approach stopping");
    let _ = cmd_vel.send(&twist(0.0, 0.0));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(width: usize, height: usize, green_rows: std::ops::Range<usize>) -> Vec<u8> {
        let mut rgb = vec![0u8; width * height * RGB_CHANNELS];
        for y in green_rows {
            for x in 0..width {
                let pixel = (y * width + x) * RGB_CHANNELS;
                rgb[pixel] = 30;
                rgb[pixel + 1] = 180;
                rgb[pixel + 2] = 40;
            }
        }
        rgb
    }

    #[test]
    fn grass_is_green_in_the_hue_band() {
        let (hue, saturation, value) = rgb_to_hsv(30, 180, 40);
        assert!((70.0..=165.0).contains(&hue), "hue {hue}");
        assert!(saturation > 0.25 && value > 0.2);
    }

    #[test]
    fn a_full_near_band_is_reached() {
        let (width, height) = (100, 100);
        // Fill the whole near band (75..100) with grass.
        let rgb = frame(width, height, 75..100);
        let gate = detect_green(&Config::default(), &rgb, width, height);
        assert!(gate.reached, "coverage {}", gate.coverage);
    }

    #[test]
    fn distant_grass_is_not_reached() {
        let (width, height) = (100, 100);
        // Grass only high in the frame (far away), none in the near band.
        let rgb = frame(width, height, 0..40);
        let gate = detect_green(&Config::default(), &rgb, width, height);
        assert!(!gate.reached, "coverage {}", gate.coverage);
    }
}
