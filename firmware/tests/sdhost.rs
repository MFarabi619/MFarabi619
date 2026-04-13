//! `describe("SD Card Round-Trip")`
//!
//! Writes a test payload to a file on the SD card and reads it back
//! through the same `firmware::filesystems::sd` infrastructure the
//! microvisor uses in production. Replaces the older SDMMC pin-probe
//! test, which became unreliable once octal PSRAM claimed GPIO 33–38.

#![no_std]
#![no_main]

extern crate alloc;

#[path = "common/mod.rs"]
mod common;

use defmt::info;

use common::{Device, tasks};

esp_bootloader_esp_idf::esp_app_desc!();

const ROUND_TRIP_FILE_NAME: &str = "RT_TEST.BIN";
const ROUND_TRIP_PAYLOAD: &[u8] =
    b"sd-card round-trip test payload \xde\xad\xbe\xef\nline two\n";

#[cfg(test)]
#[embedded_test::setup]
fn setup() {
    rtt_target::rtt_init_defmt!();
}

#[cfg(test)]
#[embedded_test::tests(default_timeout = 15, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== SD Card Round-Trip — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user writes a payload to the SD card and reads it back identically")`
    #[test]
    async fn user_writes_a_payload_and_reads_it_back_identically(
        mut device: Device,
    ) -> Result<(), &'static str> {
        tasks::sd_card::mount(&mut device)?;
        tasks::sd_card::write_then_read_back(
            &mut device,
            ROUND_TRIP_FILE_NAME,
            ROUND_TRIP_PAYLOAD,
        )?;
        info!(
            "SD card round-trip succeeded file={=str} size={=usize}",
            ROUND_TRIP_FILE_NAME,
            ROUND_TRIP_PAYLOAD.len()
        );
        Ok(())
    }
}
