use super::gpio::{Chip, Error};

const MIN_DUTY_PERCENT: f64 = 2.5;
const MAX_DUTY_PERCENT: f64 = 12.5;
const FULL_SWEEP_DEG: f64 = 180.0;

pub fn servo_duty(angle_deg: f64) -> f32 {
    (MIN_DUTY_PERCENT + (angle_deg / FULL_SWEEP_DEG) * (MAX_DUTY_PERCENT - MIN_DUTY_PERCENT)) as f32
}

pub struct Servo<'a> {
    chip: &'a Chip<'a>,
    pin: u32,
    frequency_hz: f32,
}

impl<'a> Servo<'a> {
    pub fn new(chip: &'a Chip<'a>, pin: u32, frequency_hz: f32) -> Result<Self, Error> {
        chip.claim_output(pin, false)?;
        Ok(Self {
            chip,
            pin,
            frequency_hz,
        })
    }

    pub fn angle(&self, angle_deg: f64) -> Result<(), Error> {
        self.chip
            .pwm(self.pin, self.frequency_hz, servo_duty(angle_deg))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duty_maps_sweep_to_pulse_band() {
        assert_eq!(servo_duty(0.0), 2.5);
        assert_eq!(servo_duty(90.0), 7.5);
        assert_eq!(servo_duty(180.0), 12.5);
    }
}
