#![no_std]
#![allow(unexpected_cfgs)]

extern crate alloc;

pub mod icons;
pub mod services;
pub mod shell;

#[cfg(target_arch = "xtensa")]
pub mod esp32;

#[cfg(CONFIG_NETWORKING)]
pub mod networking;
