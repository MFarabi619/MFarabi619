#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

pub mod bindings {
    include!(concat!(env!("OUT_DIR"), "/sqlite_bindings.rs"));
}

mod capi;
pub mod nostd;

#[cfg(CONFIG_SQLITE_SHELL)]
mod shell;

pub use nostd::*;
