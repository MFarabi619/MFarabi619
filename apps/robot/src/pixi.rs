use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    process::ExitStatus,
};

use rattler_shell::{run::run_command_in_environment, shell::ShellEnum};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const ACTIVATION_ENVIRONMENT: &[(&str, &str)] = &[("RMW_IMPLEMENTATION", "rmw_zenoh_cpp")];

fn project_root() -> Option<PathBuf> {
    let current = std::env::current_dir().ok()?;
    current
        .ancestors()
        .find(|directory| directory.join("pixi.toml").exists())
        .map(Path::to_path_buf)
}

pub async fn run(
    command: &[String],
    extra_environment: &[(&str, &str)],
    working_directory: Option<&str>,
) -> Result<ExitStatus, BoxError> {
    let root = project_root().ok_or("no pixi.toml found above the current directory")?;
    let prefix = root.join(".pixi/envs/default");
    let working_directory = working_directory.map(|relative| root.join(relative));

    let environment: HashMap<String, String> = ACTIVATION_ENVIRONMENT
        .iter()
        .chain(extra_environment)
        .map(|&(key, value)| (key.to_string(), value.to_string()))
        .collect();

    Ok(run_command_in_environment(
        &prefix,
        command,
        ShellEnum::default(),
        &environment,
        working_directory.as_deref(),
    )
    .await?)
}
