//! Shared scaffolding for screenplay-lite tests.
//!
//! Each test in `firmware/tests/<name>.rs` includes this module via
//! `#[path = "common/mod.rs"] mod common;`. The module is intentionally
//! kept out of `cargo`'s test auto-discovery (`autotests = false` in
//! `firmware/Cargo.toml`) so it isn't built as a test binary on its own.
//!
//! ## Layers (collapsed from Serenity's 5 → 2)
//!
//! - **`Device`** (in `setup`) — the system under test. A struct that
//!   owns hardware abilities (peripherals, buses, RTC, SD volume,
//!   WiFi controller). Built once per test by `setup::boot_device`.
//! - **`tasks::*`** — domain operations the implicit `user` performs
//!   against the device. Each task is a plain `async fn(&mut Device, ...)
//!   -> Result<T, &'static str>` with a one-line `defmt::info!`
//!   narration. Tasks group by domain (`tasks::wifi`, `tasks::sd_card`,
//!   `tasks::http`, etc.) the way web-e2e groups under `Connect`,
//!   `Swap`, `CreatePool`.
//!
//! Tests read as: "user does X to the device". The `user` actor never
//! appears in code — only in the test function name.

#![allow(dead_code, reason = "shared module; not every test exercises every helper")]

pub mod setup;
pub mod tasks;

pub use setup::Device;
