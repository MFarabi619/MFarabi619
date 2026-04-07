use loco_rs::prelude::*;

use super::common::*;

pub struct Flash;
#[async_trait]
impl Task for Flash {
    fn task(&self) -> TaskInfo {
        TaskInfo {
            name: "flash".to_string(),
            detail: "Build firmware and flash to ESP32-S3 via serial (espflash)".to_string(),
        }
    }
    async fn run(&self, app_context: &AppContext, _vars: &task::Vars) -> Result<()> {
        let settings = load_settings(app_context)?;
        let firmware = &settings.firmware;

        section("ESP32-S3 Serial Flash");

        step(1, 2, "build firmware");
        build_firmware(firmware)?;

        step(2, 2, "flash via espflash");
        let elf_path = firmware.elf_path();
        let partition_table = firmware.partition_table();
        run_command(
            "espflash",
            &[
                "flash",
                "--chip", &firmware.chip,
                "--partition-table", &partition_table,
                &elf_path,
            ],
        )?;

        success("flash complete");
        Ok(())
    }
}
