#![no_std]

extern crate alloc;

pub mod icons;
pub mod shell;

#[cfg(CONFIG_NETWORKING)]
pub mod networking;
