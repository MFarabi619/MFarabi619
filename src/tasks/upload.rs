use loco_rs::prelude::*;
use std::{
    io::{Read, Write},
    net::TcpStream,
    path::Path,
    thread,
    time::Duration,
};

use super::common::*;

pub struct Upload;
#[async_trait]
impl Task for Upload {
    fn task(&self) -> TaskInfo {
        TaskInfo {
            name: "upload".to_string(),
            detail: "Build firmware and push OTA update to ESP32-S3".to_string(),
        }
    }
    async fn run(&self, app_context: &AppContext, _vars: &task::Vars) -> Result<()> {
        let settings = load_settings(app_context)?;
        let firmware = &settings.firmware;

        section("ESP32-S3 OTA Upload");

        let endpoint = firmware.ota_endpoint();
        info(&format!("target device: {}", endpoint));

        step(1, 4, "build firmware");
        build_firmware(firmware)?;

        step(2, 4, "convert ELF to OTA image");
        let elf_path = firmware.elf_path();
        let ota_image_path = format!("{}-ota.bin", elf_path);
        run_command(
            "espflash",
            &[
                "save-image",
                "--chip", &firmware.chip,
                &elf_path,
                &ota_image_path,
            ],
        )?;

        let ota_image = Path::new(&ota_image_path);
        if !ota_image.exists() {
            error(&format!("OTA image not found at {}", ota_image_path));
            return Err(Error::Message(format!("OTA image not found at {}", ota_image_path)));
        }

        let binary = std::fs::read(ota_image).expect("Failed to read firmware file");
        let binary_crc = crc32fast::hash(&binary);
        info(&format!(
            "OTA image: {} bytes ({:.2} MiB), CRC32: {:#010x}",
            binary.len(),
            binary.len() as f64 / (1024.0 * 1024.0),
            binary_crc
        ));

        step(3, 4, &format!("connect to OTA receiver at {}", endpoint));
        let mut stream = loop {
            let mut connected = None;
            for attempt in 1..=10 {
                match TcpStream::connect(&endpoint) {
                    Ok(s) => {
                        connected = Some(s);
                        break;
                    }
                    Err(e) => {
                        info(&format!("attempt {}/10: {} (retrying in 2s)", attempt, e));
                        thread::sleep(Duration::from_secs(2));
                    }
                }
            }
            if let Some(stream) = connected {
                break stream;
            }
            info(&format!("waiting for OTA receiver at {}...", endpoint));
            thread::sleep(Duration::from_secs(2));
        };

        step(4, 4, "send OTA image");
        stream.set_read_timeout(Some(Duration::from_secs(10))).expect("set timeout");

        stream.write_all(&(binary.len() as u32).to_le_bytes()).expect("send size");
        stream.write_all(&binary_crc.to_le_bytes()).expect("send CRC");

        let mut preflight = [0u8; 1];
        stream.read_exact(&mut preflight).expect("read preflight");

        match preflight[0] {
            OTA_STATUS_READY => info("device preflight OK, streaming payload..."),
            OTA_STATUS_BEGIN_FAILED => {
                return Err(Error::Message("device rejected OTA (ota_begin failed)".into()));
            }
            code => {
                return Err(Error::Message(format!("unexpected preflight status: 0x{code:02x}")));
            }
        }

        let mut ack = [0u8; 1];
        let mut sent_bytes: usize = 0;
        let mut last_percent: usize = 0;

        for (index, chunk) in binary.chunks(8192).enumerate() {
            stream.write_all(chunk).expect("send chunk");
            stream.read_exact(&mut ack).expect("read ACK");
            sent_bytes += chunk.len();
            let percent = (sent_bytes * 100) / binary.len();
            if percent >= last_percent + 5 || percent == 100 {
                print!("\r  {:>3}% ({}/{} bytes) chunk {}", percent, sent_bytes, binary.len(), index + 1);
                std::io::stdout().flush().unwrap();
                last_percent = percent;
            }
        }

        println!();
        success("OTA complete — device is rebooting into new firmware");
        Ok(())
    }
}
