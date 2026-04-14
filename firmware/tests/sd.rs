//! `describe("SD Card")`
//!
//! Tests the SD card filesystem through the `firmware::filesystems::sd`
//! infrastructure. Mirrors the C++ test suite in `hardware/storage.cpp`.

#![no_std]
#![no_main]

extern crate alloc;

#[path = "common/mod.rs"]
mod common;

use defmt::info;
use firmware::filesystems::sd;

use common::Device;

esp_bootloader_esp_idf::esp_app_desc!();

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
        info!("=== SD Card — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user observes that the SD card reports its size")`
    #[test]
    async fn user_observes_sd_card_reports_its_size(_device: Device) -> Result<(), &'static str> {
        let snapshot = sd::snapshot();
        info!("SD card size={=u32} MiB", snapshot.sd_card_size_mb);
        defmt::assert!(snapshot.sd_card_size_mb > 0, "SD card size is 0");
        Ok(())
    }

    /// `it("user writes a file, reads it back, and deletes it")`
    #[test]
    async fn user_writes_reads_and_deletes_a_file(_device: Device) -> Result<(), &'static str> {
        let name = "RT_TEST.BIN";
        let payload = b"sd-card round-trip test payload \xde\xad\xbe\xef\nline two\n";

        sd::write_file_at("", name, payload).map_err(|_| "write failed")?;

        let readback = sd::read_file_at::<256>("", name).map_err(|_| "read failed")?;
        defmt::assert_eq!(readback.as_slice(), payload.as_slice(), "content mismatch");

        sd::delete_file(name).map_err(|_| "delete failed")?;

        let after_delete = sd::file_size(name);
        defmt::assert!(after_delete.is_err(), "file still exists after delete");

        info!("write/read/delete roundtrip verified");
        Ok(())
    }

    /// `it("user appends to a file without truncating")`
    #[test]
    async fn user_appends_to_a_file(_device: Device) -> Result<(), &'static str> {
        let name = "APPEND.TMP";
        let _ = sd::delete_file(name);

        sd::write_file_at("", name, b"hello").map_err(|_| "initial write failed")?;

        sd::write_file_chunk(name, 5, b" world").map_err(|_| "append write failed")?;

        let readback = sd::read_file_at::<256>("", name).map_err(|_| "read failed")?;
        defmt::assert_eq!(
            readback.as_slice(),
            b"hello world",
            "append content mismatch"
        );

        sd::delete_file(name).map_err(|_| "cleanup delete failed")?;

        info!("append mode verified");
        Ok(())
    }

    /// `it("user lists a directory and finds created files")`
    #[test]
    async fn user_lists_directory_and_finds_files(_device: Device) -> Result<(), &'static str> {
        sd::touch_at("", "LST_A.TMP").map_err(|_| "touch a failed")?;
        sd::touch_at("", "LST_B.TMP").map_err(|_| "touch b failed")?;

        let entries = sd::list_directory_at("/").map_err(|_| "list failed")?;

        let found_a = entries.iter().any(|e| e.name.as_str() == "LST_A.TMP");
        let found_b = entries.iter().any(|e| e.name.as_str() == "LST_B.TMP");

        defmt::assert!(found_a, "LST_A.TMP not found in listing");
        defmt::assert!(found_b, "LST_B.TMP not found in listing");

        info!("directory listing found {=usize} entries", entries.len());

        sd::delete_file("LST_A.TMP").map_err(|_| "cleanup a failed")?;
        sd::delete_file("LST_B.TMP").map_err(|_| "cleanup b failed")?;

        Ok(())
    }

    /// `it("user creates a directory and verifies it exists")`
    #[test]
    async fn user_creates_a_directory(_device: Device) -> Result<(), &'static str> {
        let dir_name = "TSTDIR";
        if !sd::directory_exists(dir_name) {
            sd::create_directory(dir_name).map_err(|_| "mkdir failed")?;
        }

        defmt::assert!(
            sd::directory_exists(dir_name),
            "directory not found after create"
        );

        sd::delete_at("/", dir_name).map_err(|_| "rmdir failed")?;

        info!("directory create/delete verified");
        Ok(())
    }

    /// `it("user copies a file and reads the copy")`
    #[test]
    async fn user_copies_a_file(_device: Device) -> Result<(), &'static str> {
        let payload = b"copy test data";
        sd::write_file_at("", "CP_SRC.TMP", payload).map_err(|_| "write src failed")?;

        sd::copy_file("CP_SRC.TMP", "CP_DST.TMP").map_err(|_| "copy failed")?;

        let readback = sd::read_file_at::<256>("", "CP_DST.TMP").map_err(|_| "read dst failed")?;
        defmt::assert_eq!(
            readback.as_slice(),
            payload.as_slice(),
            "copy content mismatch"
        );

        let _ = sd::delete_file("CP_SRC.TMP");
        let _ = sd::delete_file("CP_DST.TMP");

        info!("file copy verified");
        Ok(())
    }
}
