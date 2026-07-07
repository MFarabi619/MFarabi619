use super::gpio::{Chip, Error};

#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Velocity {
    pub left: f64,
    pub right: f64,
}

pub const HALT: Velocity = Velocity {
    left: 0.0,
    right: 0.0,
};

pub fn mix(linear: f64, angular: f64) -> Velocity {
    Velocity {
        left: linear - angular,
        right: linear + angular,
    }
}

#[derive(Clone, Copy)]
pub struct Shaping {
    pub deadzone: f64,
    pub min_duty: f64,
    pub scale: f64,
}

pub fn shape(velocity: Velocity, shaping: Shaping) -> Velocity {
    Velocity {
        left: shape_side(velocity.left, shaping),
        right: shape_side(velocity.right, shaping),
    }
}

fn shape_side(value: f64, shaping: Shaping) -> f64 {
    if value.abs() < shaping.deadzone {
        0.0
    } else {
        (value.abs() * shaping.scale)
            .clamp(shaping.min_duty, 1.0)
            .copysign(value)
    }
}

const FULL_DUTY_PERCENT: f64 = 100.0;

fn clamp_unit(value: f64) -> f64 {
    value.clamp(-1.0, 1.0)
}

#[derive(Clone, Copy)]
enum Wiring {
    DualPwm {
        forward_pin: u32,
        backward_pin: u32,
    },
    PwmDir {
        dir_pin: u32,
        pwm_pin: u32,
        forward_level: bool,
    },
}

pub struct Motor<'a> {
    chip: &'a Chip<'a>,
    wiring: Wiring,
    frequency_hz: f32,
}

impl<'a> Motor<'a> {
    pub fn dual_pwm(
        chip: &'a Chip<'a>,
        forward_pin: u32,
        backward_pin: u32,
        frequency_hz: f32,
    ) -> Result<Self, Error> {
        chip.claim_output(forward_pin, false)?;
        chip.claim_output(backward_pin, false)?;
        let motor = Self {
            chip,
            wiring: Wiring::DualPwm {
                forward_pin,
                backward_pin,
            },
            frequency_hz,
        };
        motor.drive(0.0)?;
        Ok(motor)
    }

    pub fn pwm_dir(
        chip: &'a Chip<'a>,
        dir_pin: u32,
        pwm_pin: u32,
        forward_level: bool,
        frequency_hz: f32,
    ) -> Result<Self, Error> {
        chip.claim_output(dir_pin, false)?;
        chip.claim_output(pwm_pin, false)?;
        let motor = Self {
            chip,
            wiring: Wiring::PwmDir {
                dir_pin,
                pwm_pin,
                forward_level,
            },
            frequency_hz,
        };
        motor.drive(0.0)?;
        Ok(motor)
    }

    pub fn drive(&self, speed: f64) -> Result<(), Error> {
        let speed = clamp_unit(speed);
        let duty = (speed.abs() * FULL_DUTY_PERCENT) as f32;
        match self.wiring {
            Wiring::DualPwm {
                forward_pin,
                backward_pin,
            } => {
                if speed >= 0.0 {
                    self.chip.pwm(backward_pin, self.frequency_hz, 0.0)?;
                    self.chip.pwm(forward_pin, self.frequency_hz, duty)
                } else {
                    self.chip.pwm(forward_pin, self.frequency_hz, 0.0)?;
                    self.chip.pwm(backward_pin, self.frequency_hz, duty)
                }
            }
            Wiring::PwmDir {
                dir_pin,
                pwm_pin,
                forward_level,
            } => {
                let direction_level = if speed >= 0.0 {
                    forward_level
                } else {
                    !forward_level
                };
                self.chip.write(dir_pin, direction_level)?;
                self.chip.pwm(pwm_pin, self.frequency_hz, duty)
            }
        }
    }
}

pub struct Drivetrain<'a> {
    left: Motor<'a>,
    right: Motor<'a>,
}

impl<'a> Drivetrain<'a> {
    pub fn new(left: Motor<'a>, right: Motor<'a>) -> Self {
        Self { left, right }
    }

    pub fn drive(&self, velocity: Velocity) -> Result<(), Error> {
        self.left.drive(velocity.left)?;
        self.right.drive(velocity.right)
    }
}

impl Drop for Drivetrain<'_> {
    fn drop(&mut self) {
        let _ = self.drive(HALT);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn straight_drives_both_sides_equally() {
        assert_eq!(
            mix(1.0, 0.0),
            Velocity {
                left: 1.0,
                right: 1.0,
            }
        );
    }

    #[test]
    fn spinning_in_place_opposes_the_sides() {
        assert_eq!(
            mix(0.0, 1.0),
            Velocity {
                left: -1.0,
                right: 1.0,
            }
        );
    }

    #[test]
    fn turning_biases_toward_the_slower_side() {
        let arcing = mix(1.0, 0.5);
        assert!(arcing.left < arcing.right);
    }

    #[test]
    fn no_command_is_halt() {
        assert_eq!(mix(0.0, 0.0), HALT);
    }

    #[test]
    fn shaping_zeroes_inside_the_deadzone() {
        let shaping = Shaping {
            deadzone: 0.1,
            min_duty: 0.3,
            scale: 1.0,
        };
        assert_eq!(
            shape(
                Velocity {
                    left: 0.05,
                    right: -0.05
                },
                shaping
            ),
            HALT
        );
    }

    #[test]
    fn shaping_floors_to_min_duty_and_keeps_sign() {
        let shaping = Shaping {
            deadzone: 0.1,
            min_duty: 0.3,
            scale: 1.0,
        };
        let shaped = shape(
            Velocity {
                left: 0.15,
                right: -0.15,
            },
            shaping,
        );
        assert_eq!(shaped.left, 0.3);
        assert_eq!(shaped.right, -0.3);
    }
}
