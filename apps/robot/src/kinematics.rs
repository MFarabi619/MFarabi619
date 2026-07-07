pub const WHEEL_RADIUS_METERS: f64 = 0.178;
pub const WHEEL_HALF_TRACK_METERS: f64 = 0.527;
pub const WHEEL_HALF_BASE_METERS: f64 = 0.53;

#[derive(Clone, Copy)]
pub enum WheelSide {
    Left,
    Right,
}

pub struct Wheel {
    pub joint: &'static str,
    pub mount: [f64; 3],
    pub side: WheelSide,
}

impl Wheel {
    pub fn link(&self) -> &str {
        self.joint.strip_suffix("_joint").unwrap_or(self.joint)
    }
}

pub const WHEELS: [Wheel; 4] = [
    Wheel {
        joint: "wheel_fl_joint",
        mount: [
            WHEEL_HALF_BASE_METERS,
            WHEEL_HALF_TRACK_METERS,
            WHEEL_RADIUS_METERS,
        ],
        side: WheelSide::Left,
    },
    Wheel {
        joint: "wheel_fr_joint",
        mount: [
            WHEEL_HALF_BASE_METERS,
            -WHEEL_HALF_TRACK_METERS,
            WHEEL_RADIUS_METERS,
        ],
        side: WheelSide::Right,
    },
    Wheel {
        joint: "wheel_rl_joint",
        mount: [
            -WHEEL_HALF_BASE_METERS,
            WHEEL_HALF_TRACK_METERS,
            WHEEL_RADIUS_METERS,
        ],
        side: WheelSide::Left,
    },
    Wheel {
        joint: "wheel_rr_joint",
        mount: [
            -WHEEL_HALF_BASE_METERS,
            -WHEEL_HALF_TRACK_METERS,
            WHEEL_RADIUS_METERS,
        ],
        side: WheelSide::Right,
    },
];

pub fn wheel_angular_velocities(linear_mps: f64, angular_rad_s: f64) -> (f64, f64) {
    let left = (linear_mps - angular_rad_s * WHEEL_HALF_TRACK_METERS) / WHEEL_RADIUS_METERS;
    let right = (linear_mps + angular_rad_s * WHEEL_HALF_TRACK_METERS) / WHEEL_RADIUS_METERS;
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
