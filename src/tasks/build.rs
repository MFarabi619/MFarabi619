use loco_rs::prelude::*;

use super::common::*;

pub struct Build;
#[async_trait]
impl Task for Build {
    fn task(&self) -> TaskInfo {
        TaskInfo {
            name: "build".to_string(),
            detail: "Build ESP32-S3 firmware (no flash)".to_string(),
        }
    }
    async fn run(&self, app_context: &AppContext, _vars: &task::Vars) -> Result<()> {
        let settings = load_settings(app_context)?;
        let firmware = &settings.firmware;

        section("ESP32-S3 Firmware Build");
        build_firmware(firmware)?;
        success("build complete");
        info(&format!("ELF: {}", firmware.elf_path()));
        Ok(())
    }
}
