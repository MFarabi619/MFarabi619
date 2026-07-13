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

fn shape_side(side_velocity: f64, shaping: Shaping) -> f64 {
    if side_velocity.abs() < shaping.deadzone {
        0.0
    } else {
        let travel =
            ((side_velocity.abs() - shaping.deadzone) / (1.0 - shaping.deadzone)).clamp(0.0, 1.0);
        (shaping.min_duty + travel * shaping.scale * (1.0 - shaping.min_duty))
            .copysign(side_velocity)
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

pub fn drivetrain<'a>(chip: &'a Chip<'a>) -> Result<Drivetrain<'a>, Error> {
    const LEFT_DIR_PIN: u32 = 6;
    const LEFT_PWM_PIN: u32 = 12;
    const RIGHT_DIR_PIN: u32 = 5;
    const RIGHT_PWM_PIN: u32 = 13;
    const LEFT_FORWARD_LEVEL: bool = true;
    const RIGHT_FORWARD_LEVEL: bool = false;
    const PWM_FREQUENCY_HZ: f32 = 10_000.0;
    Ok(Drivetrain::new(
        Motor::pwm_dir(
            chip,
            LEFT_DIR_PIN,
            LEFT_PWM_PIN,
            LEFT_FORWARD_LEVEL,
            PWM_FREQUENCY_HZ,
        )?,
        Motor::pwm_dir(
            chip,
            RIGHT_DIR_PIN,
            RIGHT_PWM_PIN,
            RIGHT_FORWARD_LEVEL,
            PWM_FREQUENCY_HZ,
        )?,
    ))
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

    fn approx(actual: f64, expected: f64) {
        assert!(
            (actual - expected).abs() < 1e-9,
            "got {actual}, want {expected}"
        );
    }

    #[test]
    fn shaping_starts_at_min_duty_past_the_deadzone() {
        let shaping = Shaping {
            deadzone: 0.1,
            min_duty: 0.3,
            scale: 1.0,
        };
        let shaped = shape(
            Velocity {
                left: 0.1,
                right: -0.1,
            },
            shaping,
        );
        approx(shaped.left, 0.3);
        approx(shaped.right, -0.3);
    }

    #[test]
    fn shaping_full_input_reaches_full_duty() {
        let shaping = Shaping {
            deadzone: 0.1,
            min_duty: 0.3,
            scale: 1.0,
        };
        let shaped = shape(
            Velocity {
                left: 1.0,
                right: -1.0,
            },
            shaping,
        );
        approx(shaped.left, 1.0);
        approx(shaped.right, -1.0);
    }

    #[test]
    fn shaping_is_proportional_between_floor_and_full() {
        let shaping = Shaping {
            deadzone: 0.1,
            min_duty: 0.3,
            scale: 1.0,
        };
        // halfway across the live range (0.1..1.0) -> halfway between min_duty and 1.0
        let shaped = shape(
            Velocity {
                left: 0.55,
                right: -0.55,
            },
            shaping,
        );
        approx(shaped.left, 0.65);
        approx(shaped.right, -0.65);
    }

    #[test]
    fn shaping_scale_governs_top_speed() {
        let shaping = Shaping {
            deadzone: 0.1,
            min_duty: 0.3,
            scale: 0.5,
        };
        let shaped = shape(
            Velocity {
                left: 1.0,
                right: -1.0,
            },
            shaping,
        );
        // full stick, half governor: min_duty + 0.5 * (1 - min_duty)
        approx(shaped.left, 0.65);
        approx(shaped.right, -0.65);
    }
}
