#![no_std]
#![feature(impl_trait_in_assoc_type)]

extern crate alloc;

pub mod boot;
pub mod config;
pub mod console;
pub mod hardware;
pub mod filesystems;
pub mod networking;
pub mod sensors;
pub mod power;
pub mod programs;
pub mod services;
pub mod time;
