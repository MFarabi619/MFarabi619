//! Shell: command dispatch plus prompt/path/server submodules.

use core::fmt::Write;
use core::sync::atomic::{AtomicU32, Ordering};

use alloc::string::String as AllocString;

use crate::programs::coreutils;

mod path;
mod prompt;
mod server;

pub use path::{apply_cd, display_cwd, ensure_filesystem_hierarchy, home_dir, resolve_path};
pub use prompt::{build_motd, build_prompt};
pub use server::{spawn, task};

const CTRL_L: u8 = 0x0c;
const CTRL_P: u8 = 0x10;
const CTRL_N: u8 = 0x0e;
const CTRL_W: u8 = 0x17;
const CTRL_U: u8 = 0x15;

static TERM_WIDTH: AtomicU32 = AtomicU32::new(80);

pub fn set_terminal_width(width: u32) {
    TERM_WIDTH.store(width, Ordering::Relaxed);
}

pub fn terminal_width() -> u32 {
    TERM_WIDTH.load(Ordering::Relaxed)
}

pub fn dispatch(cmd: &str, cwd: &mut AllocString) -> (AllocString, bool) {
    let cmd = cmd.trim();

    if cmd == "exit" || cmd == "quit" {
        let mut out = AllocString::new();
        let _ = write!(out, "\x1b[33mgoodbye!\x1b[0m\r\n");
        return (out, true);
    }

    if let Some(argument) = cmd.strip_prefix("cd ") {
        let previous = cwd.clone();
        apply_cd(cwd, argument);
        if !crate::filesystems::sd::directory_exists(cwd.as_str()) {
            *cwd = previous;
            return (coreutils::fmt_error(&"no such directory"), false);
        }
        return (AllocString::new(), false);
    }

    if cmd == "cd" {
        *cwd = home_dir();
        return (AllocString::new(), false);
    }

    let (name, args) = match cmd.find(' ') {
        Some(position) => (&cmd[..position], cmd[position + 1..].trim()),
        None => (cmd, ""),
    };

    let out = match name {
        "help" | "h" => coreutils::help::run(),
        "ls" => {
            if args.is_empty() {
                coreutils::ls::run(cwd)
            } else {
                let mut target = cwd.clone();
                apply_cd(&mut target, args);
                coreutils::ls::run(&target)
            }
        }
        "pwd" => {
            let mut output = AllocString::new();
            let _ = write!(output, "{}\r\n", cwd);
            output
        }
        "mkdir" => coreutils::mkdir::run(cwd, args),
        "cp" => coreutils::cp::run(args),
        "mv" => coreutils::mv::run(args),
        "rm" => coreutils::rm::run(cwd, args),
        "cat" => coreutils::cat::run(cwd, args),
        "touch" => coreutils::touch::run(cwd, args),
        "uptime" => coreutils::uptime::run(),
        "free" => coreutils::free::run(),
        "date" => coreutils::date::run(),
        "df" => coreutils::df::run(),
        "whoami" => coreutils::whoami::run(),
        "hostname" => coreutils::hostname::run(),
        "ifconfig" => coreutils::ifconfig::run(),
        "sensors" => coreutils::sensors::run(),
        "wakecause" => coreutils::wakecause::run(),
        "logstatus" => coreutils::logstatus::run(),
        "microfetch" | "fetch" => crate::programs::microfetch::run(),
        "microtop" | "top" => crate::programs::microtop::render_frame(terminal_width() as u16, 24),
        "reboot" => esp_hal::system::software_reset(),
        "clear" => {
            let mut output = AllocString::new();
            let _ = write!(output, "\x1b[2J\x1b[H");
            output
        }
        "" => AllocString::new(),
        unknown => {
            let mut output = AllocString::new();
            let _ = write!(output, "\x1b[31mcommand not found: {}\x1b[0m\r\n", unknown);
            output
        }
    };

    (out, false)
}

const HISTORY_FILE: &str = ".MSH_HIST";

pub(super) fn load_history(history: &mut crate::services::ssh::history::History<256>) {
    let home = home_dir();
    if let Ok(contents) = crate::filesystems::sd::read_file_at::<4096>(home.as_str(), HISTORY_FILE)
    {
        if let Ok(text) = core::str::from_utf8(contents.as_slice()) {
            for line in text.lines() {
                let line = line.trim();
                if !line.is_empty() {
                    let _ = history.add(line);
                }
            }
        }
    }
}

pub(super) fn save_history(history: &crate::services::ssh::history::History<256>) {
    let home = home_dir();
    let mut buf = AllocString::new();
    for entry in history.iter() {
        buf.push_str(entry);
        buf.push('\n');
    }
    let path = resolve_path(home.as_str(), HISTORY_FILE);
    let _ = crate::filesystems::sd::write_file_chunk(path.as_str(), 0, buf.as_bytes());
}
