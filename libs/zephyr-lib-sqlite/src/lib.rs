#![no_std]
#![allow(unexpected_cfgs)]
#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

extern crate alloc;

#[cfg(CONFIG_SQLITE)]
pub mod bindings {
    include!(concat!(env!("OUT_DIR"), "/sqlite_bindings.rs"));
}

#[cfg(CONFIG_SQLITE)]
mod capi;
#[cfg(CONFIG_SQLITE)]
pub mod nostd;

#[cfg(CONFIG_SQLITE_SHELL)]
mod shell;

#[cfg(CONFIG_SQLITE)]
pub use nostd::*;
