//! Domain task modules.
//!
//! Each submodule groups operations the implicit `user` performs against
//! the device. Modelled on web-e2e's `tasks.ts` (`Connect`, `Swap`,
//! `CreatePool`, …) — every task is a plain `async fn` returning
//! `Result<T, &'static str>` and logs a one-line narration via
//! `defmt::info!` on entry.

pub mod carbon_dioxide;
pub mod ds3231;
pub mod http;
pub mod i2c;
pub mod sd_card;
pub mod wifi;
