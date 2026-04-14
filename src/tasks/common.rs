use loco_rs::prelude::*;
use serde::Deserialize;
use std::process::Command;

const RESET: &str = "\x1b[0m";
const BOLD: &str = "\x1b[1m";
const CYAN: &str = "\x1b[36m";
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const RED: &str = "\x1b[31m";

// ─── Firmware settings from config/development.yaml ────────────────────────────

#[derive(Debug, Deserialize)]
pub struct Settings {
    pub firmware: FirmwareSettings,
}

#[derive(Debug, Deserialize)]
pub struct FirmwareSettings {
    pub chip: String,
    #[serde(default)]
    pub ipv4_address: Option<String>,
    #[serde(default = "default_ota_port")]
    pub ota_port: u16,
    #[serde(default)]
    pub bin: Option<String>,
    #[serde(default)]
    pub package: Option<String>,
}

fn default_ota_port() -> u16 {
    3232
}

impl FirmwareSettings {
    /// Infer the Rust target triple from the chip name.
    pub fn target(&self) -> &str {
        match self.chip.as_str() {
            "esp32" => "xtensa-esp32-none-elf",
            "esp32s2" => "xtensa-esp32s2-none-elf",
            "esp32s3" => "xtensa-esp32s3-none-elf",
            "esp32c3" => "riscv32imc-unknown-none-elf",
            "esp32c6" => "riscv32imac-unknown-none-elf",
            "esp32h2" => "riscv32imac-unknown-none-elf",
            _ => "xtensa-esp32s3-none-elf",
        }
    }

    pub fn partition_table(&self) -> String {
        format!("boards/{}.partitions.csv", self.chip)
    }

    pub fn bin_name(&self) -> &str {
        self.bin.as_deref().unwrap_or("microvisor")
    }

    pub fn package_name(&self) -> &str {
        self.package.as_deref().unwrap_or("firmware")
    }

    pub fn elf_path(&self) -> String {
        format!("target/{}/release/{}", self.target(), self.bin_name())
    }

    pub fn device_ip(&self) -> &str {
        self.ipv4_address.as_deref().unwrap_or("10.0.0.68")
    }

    pub fn ota_endpoint(&self) -> String {
        format!("{}:{}", self.device_ip(), self.ota_port)
    }
}

pub fn load_settings(app_context: &AppContext) -> Result<Settings> {
    let settings = app_context
        .config
        .settings
        .as_ref()
        .ok_or_else(|| Error::Message("missing 'settings' in config YAML".into()))?;

    serde_json::from_value(settings.clone())
        .map_err(|e| Error::Message(format!("failed to parse firmware settings: {}", e)))
}

// ─── OTA protocol constants ────────────────────────────────────────────────────

pub const OTA_STATUS_READY: u8 = 0xA5;
pub const OTA_STATUS_BEGIN_FAILED: u8 = 0xE1;

// ─── Output helpers ────────────────────────────────────────────────────────────

pub fn section(title: &str) {
    println!("\n{BOLD}{CYAN}🚀 {title}{RESET}");
}

pub fn step(index: usize, total: usize, label: &str) {
    println!("{BOLD}{CYAN}[{index}/{total}]{RESET} {label}");
}

pub fn info(message: &str) {
    println!("{CYAN}ℹ{RESET} {message}");
}

pub fn success(message: &str) {
    println!("{GREEN}✅{RESET} {message}");
}

pub fn warn(message: &str) {
    println!("{YELLOW}⚠{RESET} {message}");
}

pub fn error(message: &str) {
    println!("{RED}❌{RESET} {message}");
}

pub fn run_command(program: &str, args: &[&str]) -> Result<()> {
    let rendered = args.join(" ");
    println!("{BOLD}$ {program} {rendered}{RESET}");

    let status = Command::new(program).args(args).status()?;
    if status.success() {
        Ok(())
    } else {
        Err(Error::Message(format!(
            "command failed (exit {:?}): {} {}",
            status.code(),
            program,
            rendered
        )))
    }
}

// ─── Shared firmware operations ────────────────────────────────────────────────

pub fn build_firmware(firmware: &FirmwareSettings) -> Result<()> {
    run_command(
        "cargo",
        &[
            "+esp",
            "build",
            "--release",
            "-p",
            firmware.package_name(),
            "--bin",
            firmware.bin_name(),
            "--config",
            r#"unstable.build-std=["core","alloc"]"#,
            "--target",
            firmware.target(),
        ],
    )
}
