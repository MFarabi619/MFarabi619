use loco_rs::prelude::*;

use super::common::{info, run_command, section, step, success};

const ESP_TARGET: &str = "xtensa-esp32s3-none-elf";
const ESP_FEATURES: &str = "esp32s3";
const PACKAGE: &str = "firmware";
const BIN_NAME: &str = "esp32s3_lcd147b";
const BIN_PATH: &str = "target/xtensa-esp32s3-none-elf/release/esp32s3_lcd147b";

pub struct Lcd147b;

#[async_trait]
impl Task for Lcd147b {
    fn task(&self) -> TaskInfo {
        TaskInfo {
            name: "lcd147b".to_string(),
            detail: "Build and flash Waveshare ESP32-S3-LCD-1.47B neopixel demo".to_string(),
        }
    }

    async fn run(&self, _app_context: &AppContext, _vars: &task::Vars) -> Result<()> {
        section("ESP32-S3 LCD-1.47B");

        step(1, 2, "build board-specific firmware binary");
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
                BIN_NAME,
            ],
        )?;

        step(2, 2, "flash firmware to board");
        run_command("espflash", &["flash", BIN_PATH])?;

        success("Waveshare LCD-1.47B firmware flashed");
        info("Current binary runs neopixel hue cycle on GPIO38.");

        Ok(())
    }
}
