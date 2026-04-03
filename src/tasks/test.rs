use loco_rs::prelude::*;

use super::common::{run_command, section, step, success};

const ESP_TARGET: &str = "xtensa-esp32s3-none-elf";
const ESP_FEATURES: &str = "esp32s3";
const PACKAGE: &str = "firmware";

fn resolve_firmware_test_name(firmware_test_selector: &str) -> &str {
    match firmware_test_selector {
        "filesystem" => "http_api",
        other_test_name => other_test_name,
    }
}

fn build_base_cargo_test_arguments() -> Vec<String> {
    vec![
        "+esp".to_string(),
        "test".to_string(),
        "--package".to_string(),
        PACKAGE.to_string(),
        "--target".to_string(),
        ESP_TARGET.to_string(),
        "--config".to_string(),
        "unstable.build-std=[\"core\",\"alloc\"]".to_string(),
        "--features".to_string(),
        ESP_FEATURES.to_string(),
    ]
}

fn collect_forwarded_cargo_test_arguments(task_variables: &task::Vars) -> Vec<String> {
    let mut forwarded_cargo_test_arguments = Vec::new();

    for (argument_key, argument_value) in &task_variables.cli {
        if argument_key == "firmware" {
            let firmware_test_name = resolve_firmware_test_name(argument_value);
            forwarded_cargo_test_arguments.push("--test".to_string());
            forwarded_cargo_test_arguments.push(firmware_test_name.to_string());
            continue;
        }

        if argument_key == "test" {
            forwarded_cargo_test_arguments.push("--test".to_string());
            forwarded_cargo_test_arguments.push(argument_value.clone());
            continue;
        }

        if argument_key == "bin" {
            forwarded_cargo_test_arguments.push("--bin".to_string());
            forwarded_cargo_test_arguments.push(argument_value.clone());
            continue;
        }

        if argument_key == "example" {
            forwarded_cargo_test_arguments.push("--example".to_string());
            forwarded_cargo_test_arguments.push(argument_value.clone());
            continue;
        }

        if argument_key == "release" && argument_value == "true" {
            forwarded_cargo_test_arguments.push("--release".to_string());
            continue;
        }

        if argument_key.starts_with('-') {
            forwarded_cargo_test_arguments.push(argument_key.clone());
            if !argument_value.is_empty() && argument_value != "true" {
                forwarded_cargo_test_arguments.push(argument_value.clone());
            }
            continue;
        }

        if argument_key.starts_with("arg") {
            forwarded_cargo_test_arguments.push(argument_value.clone());
            continue;
        }

        forwarded_cargo_test_arguments.push(format!("--{}", argument_key.replace('_', "-")));
        if !argument_value.is_empty() && argument_value != "true" {
            forwarded_cargo_test_arguments.push(argument_value.clone());
        }
    }

    forwarded_cargo_test_arguments
}

fn run_embedded_test_command(
    task_variables: &task::Vars,
    optional_firmware_test_selector: Option<&str>,
) -> Result<()> {
    section("ESP32-S3 Embedded Tests");
    step(1, 1, "run firmware tests");

    let mut cargo_test_arguments = build_base_cargo_test_arguments();

    if let Some(firmware_test_selector) = optional_firmware_test_selector {
        let resolved_firmware_test_name = resolve_firmware_test_name(firmware_test_selector);
        cargo_test_arguments.push("--test".to_string());
        cargo_test_arguments.push(resolved_firmware_test_name.to_string());
    } else {
        let forwarded_cargo_test_arguments = collect_forwarded_cargo_test_arguments(task_variables);
        cargo_test_arguments.extend(forwarded_cargo_test_arguments);
    }

    let cargo_test_argument_references: Vec<&str> =
        cargo_test_arguments.iter().map(String::as_str).collect();

    run_command("cargo", &cargo_test_argument_references)?;
    success("Embedded test command completed");

    Ok(())
}

pub struct Test;
#[async_trait]
impl Task for Test {
    fn task(&self) -> TaskInfo {
        TaskInfo {
            name: "test".to_string(),
            detail: "Run ESP32-S3 firmware tests".to_string(),
        }
    }

    async fn run(&self, _app_context: &AppContext, task_variables: &task::Vars) -> Result<()> {
        run_embedded_test_command(task_variables, None)
    }
}
