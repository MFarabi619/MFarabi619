use loco_rs::prelude::*;
use std::process::Command;

const RESET: &str = "\x1b[0m";
const BOLD: &str = "\x1b[1m";
const CYAN: &str = "\x1b[36m";
const GREEN: &str = "\x1b[32m";
const YELLOW: &str = "\x1b[33m";
const RED: &str = "\x1b[31m";

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
