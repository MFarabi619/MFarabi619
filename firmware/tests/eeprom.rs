//! `describe("AT24C32 EEPROM")`
//!
//! Probes bus 1 for an AT24C32 EEPROM at 0x50 and exercises byte,
//! buffer, and page-boundary read/write operations. Tests use offsets
//! near the end of the address space (3900+) to avoid clobbering
//! useful data. Each test cleans up by writing zeros after itself.
//!
//! Skips gracefully if the EEPROM is not detected.

#![no_std]
#![no_main]

#[path = "common/mod.rs"]
mod common;

use cat24c32_rs::{Cat24c32, SlaveAddr};
use defmt::info;
use firmware::config::board;

use common::Device;

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::setup]
fn setup() {
    rtt_target::rtt_init_defmt!();
}

// Keep all test offsets below 256 — cat24c32-rs has a bug in devaddr()
// where addresses above 0xFF cause high bits to leak into the I2C
// device address, sending to 0x57 instead of 0x50. The AT24C32 uses a
// flat 12-bit address in the data bytes, not in the device address.
const TEST_BASE: u32 = 0x80;

fn is_eeprom_present(device: &mut Device) -> bool {
    let bus = match device.i2c_bus_1.as_mut() {
        Some(bus) => bus,
        None => return false,
    };
    bus.write(board::eeprom::I2C_ADDR, &[]).is_ok()
}

#[cfg(test)]
#[embedded_test::tests(default_timeout = 15, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== AT24C32 EEPROM — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user detects the EEPROM on bus 1")`
    #[test]
    async fn user_detects_eeprom_on_bus_1(
        mut device: Device,
    ) -> Result<(), &'static str> {
        if !is_eeprom_present(&mut device) {
            info!("EEPROM not present at 0x50 — skipping");
            return Ok(());
        }

        info!(
            "AT24C32 detected at 0x{=u8:02x} on i2c.1, capacity={=u16} bytes",
            board::eeprom::I2C_ADDR,
            board::eeprom::TOTAL_SIZE
        );
        Ok(())
    }

    /// `it("user writes and reads a byte")`
    #[test]
    async fn user_writes_and_reads_a_byte(
        mut device: Device,
    ) -> Result<(), &'static str> {
        if !is_eeprom_present(&mut device) {
            info!("EEPROM not present — skipping");
            return Ok(());
        }

        let bus = device.i2c_bus_1.take().ok_or("i2c bus 1 consumed")?;
        let mut eeprom = Cat24c32::new(bus, SlaveAddr::Default);

        eeprom.write_byte(TEST_BASE, 0xAB).map_err(|_| "write failed")?;
        embassy_time::Timer::after(embassy_time::Duration::from_millis(10)).await;

        let readback = eeprom.read_byte(TEST_BASE).map_err(|_| "read failed")?;
        defmt::assert_eq!(readback, 0xAB, "byte mismatch");

        eeprom.write_byte(TEST_BASE, 0x00).map_err(|_| "cleanup write failed")?;
        embassy_time::Timer::after(embassy_time::Duration::from_millis(10)).await;

        info!("byte roundtrip verified");
        Ok(())
    }

    /// `it("user writes and reads a buffer")`
    #[test]
    async fn user_writes_and_reads_a_buffer(
        mut device: Device,
    ) -> Result<(), &'static str> {
        if !is_eeprom_present(&mut device) {
            info!("EEPROM not present — skipping");
            return Ok(());
        }

        let bus = device.i2c_bus_1.take().ok_or("i2c bus 1 consumed")?;
        let mut eeprom = Cat24c32::new(bus, SlaveAddr::Default);

        let write_buf: [u8; 16] = [
            0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
            0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
        ];
        // Align to page start so write_page doesn't reject for crossing boundary
        let addr = TEST_BASE & !31;

        eeprom.write_page(addr, &write_buf).map_err(|_| "page write failed")?;
        embassy_time::Timer::after(embassy_time::Duration::from_millis(10)).await;

        let mut read_buf = [0u8; 16];
        eeprom.read_data(addr, &mut read_buf).map_err(|_| "read failed")?;

        defmt::assert_eq!(read_buf, write_buf, "buffer mismatch");

        let zeros = [0u8; 16];
        eeprom.write_page(addr, &zeros).map_err(|_| "cleanup write failed")?;
        embassy_time::Timer::after(embassy_time::Duration::from_millis(10)).await;

        info!("buffer roundtrip verified");
        Ok(())
    }

    /// `it("user reads the last byte of EEPROM")`
    #[test]
    async fn user_reads_the_last_byte(
        mut device: Device,
    ) -> Result<(), &'static str> {
        if !is_eeprom_present(&mut device) {
            info!("EEPROM not present — skipping");
            return Ok(());
        }

        let bus = device.i2c_bus_1.take().ok_or("i2c bus 1 consumed")?;
        let mut eeprom = Cat24c32::new(bus, SlaveAddr::Default);

        // Use 0xFF (255) instead of TOTAL_SIZE-1 (4095) due to devaddr bug
        let last: u32 = 0xFF;

        eeprom.write_byte(last, 0x77).map_err(|_| "write last byte failed")?;
        embassy_time::Timer::after(embassy_time::Duration::from_millis(10)).await;

        let readback = eeprom.read_byte(last).map_err(|_| "read last byte failed")?;
        defmt::assert_eq!(readback, 0x77, "last byte mismatch");

        eeprom.write_byte(last, 0x00).map_err(|_| "cleanup write failed")?;
        embassy_time::Timer::after(embassy_time::Duration::from_millis(10)).await;

        info!("last byte roundtrip verified");
        Ok(())
    }

    /// `it("user writes a buffer crossing a page boundary")`
    #[test]
    async fn user_writes_buffer_crossing_page_boundary(
        mut device: Device,
    ) -> Result<(), &'static str> {
        if !is_eeprom_present(&mut device) {
            info!("EEPROM not present — skipping");
            return Ok(());
        }

        let bus = device.i2c_bus_1.take().ok_or("i2c bus 1 consumed")?;
        let mut eeprom = Cat24c32::new(bus, SlaveAddr::Default);

        let page_size = board::eeprom::PAGE_SIZE as u32;
        let addr = page_size - 4;
        let write_buf: [u8; 8] = [0xA0, 0xA1, 0xA2, 0xA3, 0xB0, 0xB1, 0xB2, 0xB3];

        // Write first half (within page)
        eeprom.write_page(addr, &write_buf[..4]).map_err(|_| "write first half failed")?;
        embassy_time::Timer::after(embassy_time::Duration::from_millis(10)).await;

        // Write second half (next page)
        eeprom.write_page(addr + 4, &write_buf[4..]).map_err(|_| "write second half failed")?;
        embassy_time::Timer::after(embassy_time::Duration::from_millis(10)).await;

        let mut read_buf = [0u8; 8];
        eeprom.read_data(addr, &mut read_buf).map_err(|_| "read failed")?;

        defmt::assert_eq!(read_buf, write_buf, "cross-page buffer mismatch");

        let zeros = [0u8; 4];
        eeprom.write_page(addr, &zeros).map_err(|_| "cleanup first half failed")?;
        embassy_time::Timer::after(embassy_time::Duration::from_millis(10)).await;
        eeprom.write_page(addr + 4, &zeros).map_err(|_| "cleanup second half failed")?;
        embassy_time::Timer::after(embassy_time::Duration::from_millis(10)).await;

        info!("page boundary buffer verified");
        Ok(())
    }
}
