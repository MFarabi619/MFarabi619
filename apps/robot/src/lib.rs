pub mod bridge;
pub mod sim;
pub use bridge::run_bridge;
use oxidros::msg::common_interfaces::diagnostic_msgs::msg::DiagnosticStatus;
pub use sim::run_simulator;

pub const EARTH_RADIUS_METERS: f64 = 6_378_137.0;

pub mod frames {
    pub const BASE_LINK: &str = "base_link";
    pub const ODOM: &str = "odom";
    pub const CHASSIS: &str = "chassis";
    pub const CAMERA_LINK: &str = "camera_link";
    pub const CAMERA_OPTICAL: &str = "camera_optical_frame";
}

const SKY_TOP: [f64; 3] = [90.0, 140.0, 210.0];
const SKY_HORIZON: [f64; 3] = [200.0, 220.0, 245.0];
const FIELD: [f64; 3] = [78.0, 132.0, 58.0];
const FURROW: [f64; 3] = [120.0, 92.0, 60.0];
const HAZE: [f64; 3] = [200.0, 215.0, 225.0];

pub fn intrinsics(width: usize, height: usize, fov_deg: f64) -> (f64, f64, f64, f64) {
    let focal = (width as f64 / 2.0) / (fov_deg.to_radians() / 2.0).tan();
    (focal, focal, width as f64 / 2.0, height as f64 / 2.0)
}

pub fn enu_to_geodetic(east: f64, north: f64, lat0: f64, lon0: f64) -> (f64, f64) {
    let latitude = lat0 + (north / EARTH_RADIUS_METERS).to_degrees();
    let longitude = lon0 + (east / (EARTH_RADIUS_METERS * lat0.to_radians().cos())).to_degrees();
    (latitude, longitude)
}

pub fn integrate_pose(
    x: f64,
    y: f64,
    theta: f64,
    linear: f64,
    angular: f64,
    dt: f64,
) -> (f64, f64, f64) {
    let theta = theta + angular * dt;
    let x = x + linear * theta.cos() * dt;
    let y = y + linear * theta.sin() * dt;
    (x, y, theta)
}

pub fn render_field(
    x: f64,
    y: f64,
    theta: f64,
    width: usize,
    height: usize,
    fov_deg: f64,
    camera_height: f64,
) -> Vec<u8> {
    const ROW_SPACING: f64 = 0.6;
    const FOG_DISTANCE: f64 = 18.0;
    let (focal, _, center_x, center_y) = intrinsics(width, height, fov_deg);
    let (sin_theta, cos_theta) = theta.sin_cos();
    let mut pixels = vec![0u8; width * height * 3];
    for row in 0..height {
        let v = row as f64;
        for col in 0..width {
            let u = col as f64;
            let color: [f64; 3] = if v > center_y {
                let depth = v - center_y;
                let forward = camera_height * focal / depth;
                let left = forward * (center_x - u) / focal;
                let world_x = x + forward * cos_theta - left * sin_theta;
                let world_y = y + forward * sin_theta + left * cos_theta;
                let is_crop_row = ((world_y / ROW_SPACING).rem_euclid(1.0) - 0.5).abs() < 0.18;
                let is_cross_mark = (world_x.rem_euclid(1.0) - 0.5).abs() < 0.06;
                let mut ground = if is_crop_row { FURROW } else { FIELD };
                if is_cross_mark {
                    ground = ground.map(|channel| channel * 0.82);
                }
                let fog = (forward / FOG_DISTANCE).clamp(0.0, 1.0);
                std::array::from_fn(|channel| ground[channel] * (1.0 - fog) + HAZE[channel] * fog)
            } else {
                let sky_blend = (v / center_y).clamp(0.0, 1.0);
                std::array::from_fn(|channel| {
                    SKY_TOP[channel] * (1.0 - sky_blend) + SKY_HORIZON[channel] * sky_blend
                })
            };
            let base = (row * width + col) * 3;
            pixels[base..base + 3]
                .copy_from_slice(&color.map(|channel| channel.clamp(0.0, 255.0) as u8));
        }
    }
    pixels
}

const BATTERY_CRITICAL_PERCENT: f64 = 10.0;
const BATTERY_WARN_PERCENT: f64 = 30.0;

pub fn battery_diagnostic_level(percent: f64) -> u8 {
    if percent < BATTERY_CRITICAL_PERCENT {
        DiagnosticStatus::ERROR
    } else if percent < BATTERY_WARN_PERCENT {
        DiagnosticStatus::WARN
    } else {
        DiagnosticStatus::OK
    }
}

pub fn command_is_stale(age_secs: f64, threshold_secs: f64) -> bool {
    age_secs > threshold_secs
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enu_origin_maps_to_origin() {
        let (lat, lon) = enu_to_geodetic(0.0, 0.0, 45.4215, -75.6972);
        assert_eq!(lat, 45.4215);
        assert_eq!(lon, -75.6972);
    }

    #[test]
    fn enu_moving_north_raises_latitude_only() {
        let (lat, lon) = enu_to_geodetic(0.0, 100.0, 45.4215, -75.6972);
        assert!(lat > 45.4215);
        assert_eq!(lon, -75.6972);
    }

    #[test]
    fn intrinsics_center_is_half_the_frame() {
        let (_, _, cx, cy) = intrinsics(640, 400, 70.0);
        assert_eq!(cx, 320.0);
        assert_eq!(cy, 200.0);
    }

    #[test]
    fn driving_straight_moves_along_x() {
        let (x, y, theta) = integrate_pose(0.0, 0.0, 0.0, 1.0, 0.0, 1.0);
        assert!(x > 0.0);
        assert_eq!(y, 0.0);
        assert_eq!(theta, 0.0);
    }

    #[test]
    fn turning_changes_heading() {
        let (_, _, theta) = integrate_pose(0.0, 0.0, 0.0, 0.0, 1.0, 0.5);
        assert!(theta > 0.0);
    }

    #[test]
    fn resting_stays_put() {
        let resting = integrate_pose(2.0, 3.0, 1.0, 0.0, 0.0, 1.0);
        assert_eq!(resting, (2.0, 3.0, 1.0));
    }

    #[test]
    fn render_produces_rgb_frame_of_the_right_size() {
        let frame = render_field(0.0, 0.0, 0.0, 320, 200, 70.0, 0.2);
        assert_eq!(frame.len(), 320 * 200 * 3);
    }

    #[test]
    fn sky_reads_blue_ground_reads_green() {
        let (w, h) = (320usize, 200usize);
        let frame = render_field(0.0, 0.0, 0.0, w, h, 70.0, 0.2);
        let channel_mean = |rows: std::ops::Range<usize>, channel: usize| -> f64 {
            let mut sum = 0.0;
            let mut count = 0.0;
            for row in rows {
                for col in 0..w {
                    sum += frame[(row * w + col) * 3 + channel] as f64;
                    count += 1.0;
                }
            }
            sum / count
        };
        assert!(channel_mean(0..h / 4, 2) > channel_mean(0..h / 4, 1));
        assert!(channel_mean(h * 3 / 4..h, 1) > channel_mean(h * 3 / 4..h, 2));
    }

    #[test]
    fn turning_changes_the_view() {
        let straight = render_field(0.0, 0.0, 0.0, 320, 200, 70.0, 0.2);
        let turned = render_field(0.0, 0.0, 0.6, 320, 200, 70.0, 0.2);
        assert_ne!(straight, turned);
    }

    #[test]
    fn driving_forward_changes_the_view() {
        let here = render_field(0.0, 0.0, 0.0, 320, 200, 70.0, 0.2);
        let ahead = render_field(0.5, 0.0, 0.0, 320, 200, 70.0, 0.2);
        assert_ne!(here, ahead);
    }

    #[test]
    fn battery_full_is_ok() {
        assert_eq!(battery_diagnostic_level(80.0), DiagnosticStatus::OK);
    }

    #[test]
    fn battery_low_warns() {
        assert_eq!(battery_diagnostic_level(20.0), DiagnosticStatus::WARN);
    }

    #[test]
    fn battery_critical_errors() {
        assert_eq!(battery_diagnostic_level(5.0), DiagnosticStatus::ERROR);
    }

    #[test]
    fn fresh_command_is_not_stale() {
        assert!(!command_is_stale(0.5, 2.0));
    }

    #[test]
    fn old_command_is_stale() {
        assert!(command_is_stale(3.0, 2.0));
    }
}
