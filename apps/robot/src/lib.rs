pub mod bridge;
pub mod renderer;
pub mod sim;
pub use bridge::run_bridge;
use oxidros::msg::common_interfaces::diagnostic_msgs::msg::DiagnosticStatus;
pub use renderer::CameraRenderer;
pub use sim::run_simulator;

pub const EARTH_RADIUS_METERS: f64 = 6_378_137.0;

pub mod frames {
    pub const BASE_LINK: &str = "base_link";
    pub const ODOM: &str = "odom";
    pub const CHASSIS: &str = "chassis";
    pub const CAMERA_LINK: &str = "camera_link";
    pub const CAMERA_OPTICAL: &str = "camera_optical_frame";
}

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
