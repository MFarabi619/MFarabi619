use loco_rs::prelude::*;

use super::common::{run_command, section, step, success};

const ESP_TARGET: &str = "xtensa-esp32s3-none-elf";
const ESP_FEATURES: &str = "esp32s3";
const PACKAGE: &str = "firmware";
const APP_FIRMWARE_PATH: &str =
    "target/xtensa-esp32s3-none-elf/release/esp32s3";

pub struct Build;
#[async_trait]
impl Task for Build {
    fn task(&self) -> TaskInfo {
        TaskInfo {
            name: "build".to_string(),
            detail: "Build ESP32-S3 app firmware (esp32s3)".to_string(),
        }
    }
    async fn run(&self, _app_context: &AppContext, _vars: &task::Vars) -> Result<()> {
        section("ESP32-S3 Build");
        step(1, 1, "build app firmware");

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

        success(&format!("Build complete: {}", APP_FIRMWARE_PATH));

        Ok(())
    }
}
