use std::sync::LazyLock;

use robot_description::{
    datums::WHEEL_TREAD_DIAMETER_MM,
    placement::{joint_table, wheel_origin, Corner},
    MM_TO_M,
};

pub const WHEEL_RADIUS_METERS: f64 = WHEEL_TREAD_DIAMETER_MM / 2.0 * MM_TO_M;

pub struct Wheel {
    pub joint_name: &'static str,
    pub corner: Corner,
}

pub static WHEELS: LazyLock<[Wheel; 4]> = LazyLock::new(|| {
    let joints = joint_table();
    Corner::ALL.map(|corner| {
        let wheel_link = corner.wheel_link();
        let joint_name = joints
            .iter()
            .find(|joint| joint.child == wheel_link)
            .expect("description declares a joint for every wheel link")
            .name;
        Wheel { joint_name, corner }
    })
});

pub fn half_track_meters() -> f64 {
    wheel_origin(Corner::FrontLeft).y * MM_TO_M
}

pub fn wheel_angular_velocities(linear_mps: f64, angular_rad_s: f64) -> (f64, f64) {
    let half_track = half_track_meters();
    let left = (linear_mps - angular_rad_s * half_track) / WHEEL_RADIUS_METERS;
    let right = (linear_mps + angular_rad_s * half_track) / WHEEL_RADIUS_METERS;
    (left, right)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn straight_spins_both_wheels_equally_forward() {
        let (left, right) = wheel_angular_velocities(1.0, 0.0);
        assert_eq!(left, right);
        assert!(left > 0.0);
    }

    #[test]
    fn spinning_in_place_counter_rotates_the_wheels() {
        let (left, right) = wheel_angular_velocities(0.0, 1.0);
        assert_eq!(left, -right);
    }

}
