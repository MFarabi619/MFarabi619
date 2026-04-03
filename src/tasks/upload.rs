use loco_rs::prelude::*;
use std::{
    io::{Read, Write},
    net::TcpStream,
    path::Path,
    thread,
    time::Duration,
};

use super::common::{error, info, run_command, section, step, success};

const ESP_TARGET: &str = "xtensa-esp32s3-none-elf";
const ESP_FEATURES: &str = "esp32s3";
const PACKAGE: &str = "firmware";
const APP_ELF_PATH: &str = "target/xtensa-esp32s3-none-elf/release/esp32s3";
const APP_OTA_IMAGE_PATH: &str = "target/xtensa-esp32s3-none-elf/release/esp32s3-ota.bin";
const PARTITION_TABLE: &str = "firmware/partitions.csv";
const OTA_DEVICE_PORT: u16 = 3232;
const OTA_STATUS_READY: u8 = 0xA5;
const OTA_STATUS_BEGIN_FAILED: u8 = 0xE1;

fn ota_device_ip() -> String {
    std::env::var("OTA_DEVICE_IP").unwrap_or_else(|_| "127.0.0.1".to_string())
}

fn ota_device_endpoint() -> String {
    format!("{}:{}", ota_device_ip(), OTA_DEVICE_PORT)
}

pub struct Upload;
#[async_trait]
impl Task for Upload {
    fn task(&self) -> TaskInfo {
        TaskInfo {
            name: "upload".to_string(),
            detail: "Build app firmware and push OTA to ESP32-S3 listener".to_string(),
        }
    }
    async fn run(&self, _app_context: &AppContext, _vars: &task::Vars) -> Result<()> {
        section("ESP32-S3 OTA Upload");
        info("Push OTA mode enabled (host-listener port is not used in this flow)");

        step(1, 4, "build app firmware (ELF)");
        run_command(
            "cargo",
            &[
                "+esp",
                "build",
                "--release",
                "--package",
                PACKAGE,
                "--config",
                "unstable.build-std=[\"core\",\"alloc\"]",
                "--target",
                ESP_TARGET,
                "--features",
                ESP_FEATURES,
                "--bin",
                "esp32s3",
            ],
        )?;

        step(2, 4, "convert ELF to OTA image");
        run_command(
            "espflash",
            &[
                "save-image",
                "--chip",
                "esp32s3",
                "--target-app-partition",
                "ota_0",
                "--partition-table",
                PARTITION_TABLE,
                APP_ELF_PATH,
                APP_OTA_IMAGE_PATH,
            ],
        )?;

        let endpoint = ota_device_endpoint();

        step(3, 4, &format!("connect to OTA receiver at {}", endpoint));

        let firmware_path = Path::new(APP_OTA_IMAGE_PATH);
        if !firmware_path.exists() {
            error(&format!("OTA image not found at {}", APP_OTA_IMAGE_PATH));
            return Err(Error::Message(format!(
                "OTA image not found at {}",
                APP_OTA_IMAGE_PATH
            )));
        }

        let binary = std::fs::read(firmware_path).expect("Failed to read firmware file");
        let binary_crc = crc32fast::hash(&binary);

        println!(
            "OTA image size: {} bytes ({:.2} MiB)",
            binary.len(),
            binary.len() as f64 / (1024.0 * 1024.0)
        );
        println!("CRC32: {:#010x}", binary_crc);

        let mut stream = loop {
            let mut connected = None;
            for attempt in 1..=10 {
                match TcpStream::connect(&endpoint) {
                    Ok(s) => {
                        connected = Some(s);
                        break;
                    }
                    Err(e) => {
                        info(&format!(
                            "Connect attempt {}/10 failed: {} (retrying in 2s)",
                            attempt, e
                        ));
                        thread::sleep(Duration::from_secs(2));
                    }
                }
            }

            if let Some(stream) = connected {
                break stream;
            }

            info(&format!("Still waiting for OTA receiver at {}...", endpoint));
            thread::sleep(Duration::from_secs(2));
        };

        step(4, 4, "send OTA image");
        info("Connected. Streaming OTA payload...");

        stream
            .set_read_timeout(Some(Duration::from_secs(10)))
            .expect("Failed to set TCP read timeout");

        stream
            .write_all(&(binary.len() as u32).to_le_bytes())
            .expect("Failed to send size");
        stream
            .write_all(&binary_crc.to_le_bytes())
            .expect("Failed to send CRC");

        let mut preflight = [0u8; 1];
        stream
            .read_exact(&mut preflight)
            .expect("Failed to read OTA preflight status");

        match preflight[0] {
            OTA_STATUS_READY => info("Device preflight OK, streaming payload..."),
            OTA_STATUS_BEGIN_FAILED => {
                return Err(Error::Message(
                    "device rejected OTA preflight (ota_begin failed)".to_string(),
                ));
            }
            code => {
                return Err(Error::Message(format!(
                    "unexpected OTA preflight status byte: 0x{code:02x}"
                )));
            }
        }

        let chunks = binary.chunks(8192);
        let mut ack = [0u8; 1];
        let mut sent_bytes: usize = 0;
        let mut last_shown_percent: usize = 0;

        for (index, chunk) in chunks.enumerate() {
            stream.write_all(chunk).expect("Failed to send chunk");
            stream.read_exact(&mut ack).expect("Failed to read ACK");
            sent_bytes += chunk.len();

            let progress = (sent_bytes * 100) / binary.len();
            if progress >= last_shown_percent + 5 || progress == 100 {
                print!(
                    "\r📦 Upload progress: {:>3}% ({}/{} bytes) chunk {}",
                    progress,
                    sent_bytes,
                    binary.len(),
                    index + 1
                );
                std::io::stdout().flush().unwrap();
                last_shown_percent = progress;
            }
        }

        println!("\n");
        success("OTA image sent successfully");
        info("Device is rebooting into the new firmware.");

        Ok(())
    }
}
