use std::sync::LazyLock;

use robot_description::{
    datums::WHEEL_TREAD_DIAMETER_MILLIMETERS,
    dimensions::Dimensions,
    placement::{joint_table, wheel_origin, Corner},
    METERS_PER_MILLIMETER,
};

pub const WHEEL_RADIUS_METERS: f64 = WHEEL_TREAD_DIAMETER_MILLIMETERS / 2.0 * METERS_PER_MILLIMETER;

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

pub fn half_track_meters() -> f64 {
    let dimensions = Dimensions {
        frame_length_millimeters: 1219.2,
        frame_width_millimeters: 1000.0,
        frame_top_z_millimeters: 300.0,
        rear_axle_inset_millimeters: 85.0,
        has_deck_equipment: true,
        has_cross_rails: false,
    };
    wheel_origin(Corner::RearLeft, &dimensions).y * METERS_PER_MILLIMETER
}

pub fn wheel_angular_velocities(linear_meters_per_second: f64, angular_radians_per_second: f64) -> (f64, f64) {
    let half_track = half_track_meters();
    let left = (linear_meters_per_second - angular_radians_per_second * half_track) / WHEEL_RADIUS_METERS;
    let right = (linear_meters_per_second + angular_radians_per_second * half_track) / WHEEL_RADIUS_METERS;
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
