#![no_std]
#![allow(unused_imports)]

extern crate alloc;

pub mod commands;
pub mod config;
pub mod theme;
pub mod tui;

pub use tui::input::Key;
pub use tui::state::App;
pub use tui::layout::layout;
