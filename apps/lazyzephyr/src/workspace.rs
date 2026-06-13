use std::process::Command;

use lazyzephyr_core::commands::workspace::{ConfigEntry, WestBoard, WestProject, WestWorkspace};

pub fn load() -> WestWorkspace {
    WestWorkspace {
        config:   load_config(),
        projects: load_projects(),
        boards:   load_boards(),
    }
}

fn run(args: &[&str]) -> Option<String> {
    let output = Command::new("west").args(args).output().ok()?;
    if !output.status.success() {
        eprintln!("lazyzephyr: `west {}` exited with {}", args.join(" "), output.status);
        return None;
    }
    String::from_utf8(output.stdout).ok()
}

fn load_config() -> Vec<ConfigEntry> {
    let Some(output) = run(&["config", "-l"]) else { return Vec::new(); };
    output.lines()
        .filter_map(|line| line.split_once('='))
        .map(|(k, v)| ConfigEntry { key: k.trim().into(), value: v.trim().into() })
        .collect()
}

fn load_projects() -> Vec<WestProject> {
    let Some(output) = run(&["list", "-f", "{name}\t{path}\t{revision}\t{url}"]) else { return Vec::new(); };
    output.lines()
        .filter_map(|line| {
            let mut fields = line.split('\t');
            Some(WestProject {
                name:     fields.next()?.into(),
                path:     fields.next()?.into(),
                revision: fields.next()?.into(),
                url:      fields.next().unwrap_or("").into(),
            })
        })
        .collect()
}

fn load_boards() -> Vec<WestBoard> {
    let Some(output) = run(&["boards", "-f", "{name}\t{full_name}\t{vendor}"]) else { return Vec::new(); };
    output.lines()
        .filter_map(|line| {
            let mut fields = line.split('\t');
            Some(WestBoard {
                name:      fields.next()?.into(),
                full_name: fields.next()?.into(),
                vendor:    fields.next().unwrap_or("").into(),
            })
        })
        .collect()
}
