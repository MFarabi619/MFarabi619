use super::gpio::{Chip, Error};

pub struct Led<'a> {
    chip: &'a Chip<'a>,
    line: u32,
}

impl<'a> Led<'a> {
    pub fn new(chip: &'a Chip<'a>, line: u32) -> Result<Self, Error> {
        chip.claim_output(line, false)?;
        Ok(Self { chip, line })
    }

    pub fn set(&self, is_on: bool) -> Result<(), Error> {
        self.chip.write(self.line, is_on)
    }

    pub fn on(&self) -> Result<(), Error> {
        self.set(true)
    }

    pub fn off(&self) -> Result<(), Error> {
        self.set(false)
    }
}
