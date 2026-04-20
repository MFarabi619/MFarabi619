#![no_std]
#![feature(impl_trait_in_assoc_type)]
#![allow(unexpected_cfgs)]

extern crate alloc;

#[cfg(not(feature = "zephyr"))]
use panic_rtt_target as _;

#[cfg(feature = "zephyr")]
mod zephyr_main;

#[cfg(not(feature = "zephyr"))]
pub mod boot;
#[cfg(not(feature = "zephyr"))]
pub mod config;
#[cfg(not(feature = "zephyr"))]
pub mod console;
#[cfg(not(feature = "zephyr"))]
pub mod hardware;
#[cfg(not(feature = "zephyr"))]
pub mod filesystems;
#[cfg(not(feature = "zephyr"))]
pub mod networking;
#[cfg(not(feature = "zephyr"))]
pub mod sensors;
#[cfg(not(feature = "zephyr"))]
pub mod power;
#[cfg(not(feature = "zephyr"))]
pub mod programs;
#[cfg(not(feature = "zephyr"))]
pub mod services;
#[cfg(not(feature = "zephyr"))]
pub mod time;
