use std::{fs, path::PathBuf};

use etcetera::{AppStrategy, AppStrategyArgs, choose_app_strategy};
use lazyzephyr_core::config::UserConfig;

pub fn load() -> UserConfig {
    let path = match config_path() {
        Some(p) => p,
        None => return UserConfig::default(),
    };
    let bytes = match fs::read(&path) {
        Ok(b) => b,
        Err(_) => return UserConfig::default(),
    };
    match serde_yaml_ng::from_slice::<UserConfig>(&bytes) {
        Ok(cfg) => cfg,
        Err(error) => {
            eprintln!("lazyzephyr: failed to parse {}: {error}", path.display());
            UserConfig::default()
        }
    }
}

fn config_path() -> Option<PathBuf> {
    let local = PathBuf::from("apps/lazyzephyr/config.yml");
    if local.exists() {
        return Some(local);
    }
    let strategy = choose_app_strategy(AppStrategyArgs {
        top_level_domain: "mfarabi.sh".into(),
        author: "Mumtahin Farabi".into(),
        app_name: "lazyzephyr".into(),
    })
    .ok()?;
    Some(strategy.config_dir().join("config.yml"))
}
