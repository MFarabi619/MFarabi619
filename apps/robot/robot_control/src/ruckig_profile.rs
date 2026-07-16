use oxidros::core::parameter::Parameters;
use rsruckig::prelude::{
    daov_stack, ControlInterface, IgnoreErrorHandler, InputParameter, OutputParameter, Ruckig,
    RuckigResult,
};

use crate::params::f64_param;

const LINEAR: usize = 0;
const ANGULAR: usize = 1;
const MAX_VELOCITY: f64 = 100.0;

#[derive(Clone, Copy)]
pub struct AxisLimits {
    pub max_acceleration: f64,
    pub max_deceleration: f64,
    pub max_jerk: f64,
}

pub fn axis_limits(store: &Parameters, axis: &str, default: AxisLimits) -> AxisLimits {
    AxisLimits {
        max_acceleration: f64_param(store, &format!("{axis}.max_acceleration"), default.max_acceleration),
        max_deceleration: f64_param(store, &format!("{axis}.max_deceleration"), default.max_deceleration),
        max_jerk: f64_param(store, &format!("{axis}.max_jerk"), default.max_jerk),
    }
}

pub const DEFAULT_UPDATE_RATE: f64 = 50.0;

pub const DEFAULT_LINEAR: AxisLimits = AxisLimits {
    max_acceleration: 8.0,
    max_deceleration: 16.0,
    max_jerk: 60.0,
};

pub const DEFAULT_ANGULAR: AxisLimits = AxisLimits {
    max_acceleration: 10.0,
    max_deceleration: 20.0,
    max_jerk: 70.0,
};

pub struct RuckigProfile {
    generator: Ruckig<2, IgnoreErrorHandler>,
    input: InputParameter<2>,
    output: OutputParameter<2>,
}

impl RuckigProfile {
    pub fn new(delta_time: f64, linear: AxisLimits, angular: AxisLimits) -> Self {
        let mut input = InputParameter::<2>::new(None);
        input.control_interface = ControlInterface::Velocity;
        for axis in [LINEAR, ANGULAR] {
            input.max_velocity[axis] = MAX_VELOCITY;
            input.target_acceleration[axis] = 0.0;
        }
        input.max_acceleration[LINEAR] = linear.max_acceleration;
        input.max_jerk[LINEAR] = linear.max_jerk;
        input.max_acceleration[ANGULAR] = angular.max_acceleration;
        input.max_jerk[ANGULAR] = angular.max_jerk;
        input.min_acceleration =
            Some(daov_stack![-linear.max_deceleration, -angular.max_deceleration]);
        Self {
            generator: Ruckig::new(None, delta_time),
            input,
            output: OutputParameter::<2>::new(None),
        }
    }

    pub fn reset(&mut self) {
        for axis in [LINEAR, ANGULAR] {
            self.input.current_position[axis] = 0.0;
            self.input.current_velocity[axis] = 0.0;
            self.input.current_acceleration[axis] = 0.0;
            self.input.target_velocity[axis] = 0.0;
        }
    }

    pub fn step(&mut self, linear: f64, angular: f64) -> (f64, f64) {
        self.input.target_velocity[LINEAR] = linear;
        self.input.target_velocity[ANGULAR] = angular;
        if let Ok(RuckigResult::Working | RuckigResult::Finished) =
            self.generator.update(&self.input, &mut self.output)
        {
            self.output.pass_to_input(&mut self.input);
        }
        (
            self.input.current_velocity[LINEAR],
            self.input.current_velocity[ANGULAR],
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const DT: f64 = 0.02;
    const LIMITS: AxisLimits = AxisLimits {
        max_acceleration: 8.0,
        max_deceleration: 16.0,
        max_jerk: 60.0,
    };

    #[test]
    fn releasing_eases_back_to_zero() {
        let mut profile = RuckigProfile::new(DT, LIMITS, LIMITS);
        let mut linear = 0.0;
        for _ in 0..200 {
            linear = profile.step(1.0, 0.0).0;
        }
        assert!(linear > 0.5);
        for _ in 0..200 {
            linear = profile.step(0.0, 0.0).0;
        }
        assert!(
            linear.abs() < 0.05,
            "should ease back to zero, got {linear}"
        );
    }

    #[test]
    fn harder_decel_cap_shortens_stops_once_it_binds() {
        // The decel cap only bites above the jerk-limited regime
        // (sqrt(cruise * max_jerk) > max_deceleration), so cruise fast.
        const CRUISE: f64 = 8.0;
        let mut profile = RuckigProfile::new(DT, LIMITS, LIMITS);

        let mut accel_ticks = 0;
        while profile.step(CRUISE, 0.0).0 < CRUISE - 0.01 {
            accel_ticks += 1;
            assert!(accel_ticks < 1000, "never reached cruise");
        }
        let mut decel_ticks = 0;
        while profile.step(0.0, 0.0).0 > 0.01 {
            decel_ticks += 1;
            assert!(decel_ticks < 1000, "never stopped");
        }
        assert!(
            decel_ticks < accel_ticks,
            "stop ({decel_ticks} ticks) should beat launch ({accel_ticks} ticks)"
        );
    }

    #[test]
    fn axes_ramp_together_and_independently() {
        let mut profile = RuckigProfile::new(DT, LIMITS, LIMITS);
        let (linear, angular) = profile.step(1.0, -1.0);
        assert!(linear > 0.0 && angular < 0.0, "got ({linear}, {angular})");
    }
}
