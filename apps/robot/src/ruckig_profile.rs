use rsruckig::prelude::{
    ControlInterface, IgnoreErrorHandler, InputParameter, OutputParameter, Ruckig, RuckigResult,
};

const LINEAR: usize = 0;
const ANGULAR: usize = 1;
const VELOCITY_CEILING: f64 = 100.0;

#[derive(Clone, Copy)]
pub struct AxisLimits {
    pub max_acceleration: f64,
    pub max_jerk: f64,
}

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
            input.max_velocity[axis] = VELOCITY_CEILING;
            input.target_acceleration[axis] = 0.0;
        }
        input.max_acceleration[LINEAR] = linear.max_acceleration;
        input.max_jerk[LINEAR] = linear.max_jerk;
        input.max_acceleration[ANGULAR] = angular.max_acceleration;
        input.max_jerk[ANGULAR] = angular.max_jerk;
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
        max_jerk: 60.0,
    };

    #[test]
    fn eases_up_toward_the_target() {
        let mut profile = RuckigProfile::new(DT, LIMITS, LIMITS);
        let first = profile.step(1.0, 0.0).0;
        assert!(
            first < 1.0,
            "should not jump straight to target, got {first}"
        );
        let mut linear = first;
        for _ in 0..200 {
            linear = profile.step(1.0, 0.0).0;
        }
        assert!(
            (linear - 1.0).abs() < 0.05,
            "should reach the target, got {linear}"
        );
    }

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
    fn axes_ramp_together_and_independently() {
        let mut profile = RuckigProfile::new(DT, LIMITS, LIMITS);
        let (linear, angular) = profile.step(1.0, -1.0);
        assert!(linear > 0.0 && angular < 0.0, "got ({linear}, {angular})");
    }
}
