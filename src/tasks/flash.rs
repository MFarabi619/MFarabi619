use loco_rs::prelude::*;

use super::common::{info, run_command, section, step, success};

const ESP_TARGET: &str = "xtensa-esp32s3-none-elf";
const ESP_FEATURES: &str = "esp32s3";
const PACKAGE: &str = "firmware";
const PARTITION_TABLE: &str = "firmware/partitions.csv";
const FIRMWARE_BIN_PATH: &str = "target/xtensa-esp32s3-none-elf/release/esp32s3";
const PROBE_LOG_FORMAT: &str =
    "{[{L:bold:green:4}]%bold} {ff:bold:magenta}:{l:bold:cyan} :: {s:bold:white}";

pub struct Flash;
#[async_trait]
impl Task for Flash {
    fn task(&self) -> TaskInfo {
        TaskInfo {
            name: "flash".to_string(),
            detail: "Build, flash, and monitor main ESP32-S3 firmware".to_string(),
        }
    }
    async fn run(&self, _app_context: &AppContext, _vars: &task::Vars) -> Result<()> {
        section("ESP32-S3 Flash + Monitor");

        step(1, 4, "build main firmware binary");
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

        step(2, 4, "show partition table layout");
        run_command("espflash", &["partition-table", PARTITION_TABLE])?;

        step(3, 4, "flash main firmware with partition table");
        run_command(
            "espflash",
            &[
                "flash",
                "--partition-table",
                PARTITION_TABLE,
                "--erase-parts",
                "otadata",
                FIRMWARE_BIN_PATH,
            ],
        )?;

        success("Main firmware flashed");
        info("Device is rebooting into main firmware with OTA receiver on port 3232.");

        step(4, 4, "attach RTT monitor (Ctrl+C to stop)");
        run_command(
            "probe-rs",
            &[
                "run",
                "--chip",
                "esp32s3",
                "--idf-partition-table",
                PARTITION_TABLE,
                "--log-format",
                PROBE_LOG_FORMAT,
                FIRMWARE_BIN_PATH,
            ],
        )?;

        Ok(())
    }
}
