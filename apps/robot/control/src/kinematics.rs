use std::sync::LazyLock;

use robot_description::{
    datums::WHEEL_TREAD_DIAMETER_MM,
    dimensions::Dimensions,
    placement::{joint_table, wheel_origin, Corner},
    MM_TO_M,
};

pub const WHEEL_RADIUS_M: f64 = WHEEL_TREAD_DIAMETER_MM / 2.0 * MM_TO_M;

pub struct Wheel {
    pub joint_name: &'static str,
    pub corner: Corner,
}

pub static DRIVE_WHEELS: LazyLock<[Wheel; 2]> = LazyLock::new(|| {
    let joints = joint_table();
    Corner::REAR.map(|corner| {
        let wheel_link = corner.wheel_link();
        let joint_name = joints
            .iter()
            .find(|joint| joint.child == wheel_link)
            .expect("description declares a joint for every wheel link")
            .name;
        Wheel { joint_name, corner }
    })
});

pub fn half_track_m() -> f64 {
    let dimensions = Dimensions {
        frame_length_mm: 1219.2,
        frame_width_mm: 1000.0,
        frame_top_z_mm: 300.0,
        rear_axle_inset_mm: 85.0,
        has_deck_equipment: true,
        has_cross_rails: false,
    };
    wheel_origin(Corner::RearLeft, &dimensions).y * MM_TO_M
}

pub fn wheel_angular_velocities(linear_m_per_s: f64, angular_rad_per_s: f64) -> (f64, f64) {
    let half_track = half_track_m();
    let left = (linear_m_per_s - angular_rad_per_s * half_track) / WHEEL_RADIUS_M;
    let right = (linear_m_per_s + angular_rad_per_s * half_track) / WHEEL_RADIUS_M;
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
