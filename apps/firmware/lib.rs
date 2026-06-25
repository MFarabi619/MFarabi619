#![cfg_attr(target_os = "none", no_std)]
#![allow(unexpected_cfgs)]

#[cfg(target_os = "none")]
include!(concat!(env!("BUILD_DIR"), "/rust/probe_rs_meta.rs"));

#[cfg(target_os = "none")]
extern crate alloc;

pub mod ui;

#[cfg(target_os = "none")]
pub mod programs;

#[cfg(all(target_os = "none", target_arch = "xtensa"))]
pub mod services;

#[cfg(all(target_os = "none", target_arch = "xtensa", CONFIG_NETWORKING))]
pub mod networking;

#[cfg(all(target_os = "none", target_arch = "xtensa", CONFIG_ZTEST))]
pub mod bdd;

#[cfg_attr(target_arch = "xtensa",                               path = "arch/xtensa.rs")]
#[cfg_attr(all(target_os = "none", not(target_arch = "xtensa")), path = "arch/cortex_m.rs")]
#[cfg(target_os = "none")]
mod arch;
