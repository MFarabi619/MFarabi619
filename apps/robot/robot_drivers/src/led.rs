use super::gpio::{Chip, Error};

pub struct Led<'a> {
    chip: &'a Chip<'a>,
    pin: u32,
}

impl<'a> Led<'a> {
    pub fn new(chip: &'a Chip<'a>, pin: u32) -> Result<Self, Error> {
        chip.claim_output(pin, false)?;
        Ok(Self { chip, pin })
    }

    pub fn set(&self, is_on: bool) -> Result<(), Error> {
        self.chip.write(self.pin, is_on)
    }

    pub fn on(&self) -> Result<(), Error> {
        self.set(true)
    }

    pub fn off(&self) -> Result<(), Error> {
        self.set(false)
    }
}
