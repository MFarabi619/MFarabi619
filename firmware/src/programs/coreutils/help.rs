use core::fmt::Write;
use alloc::string::String as AllocString;

pub fn run() -> AllocString {
    let mut out = AllocString::new();

    let commands = [
        ("ls", "List files"),
        ("cd <dir>", "Change directory"),
        ("pwd", "Print working directory"),
        ("mkdir <name>", "Create directory"),
        ("cat <file>", "View file contents"),
        ("touch <file>", "Create empty file"),
        ("cp <src> <dst>", "Copy file"),
        ("mv <src> <dst>", "Move/rename file"),
        ("rm <file>", "Delete file"),
        ("uptime", "Show uptime"),
        ("free", "Memory usage"),
        ("date", "Current date/time"),
        ("df", "Disk usage"),
        ("whoami", "Current user"),
        ("hostname", "Device hostname"),
        ("ifconfig", "Network interface info"),
        ("sensors", "Hardware sensors"),
        ("microfetch", "System info"),
        ("reboot", "Restart device"),
        ("clear", "Clear screen"),
        ("help", "This help"),
        ("exit", "Disconnect"),
    ];

    let _ = write!(out, "\r\n");
    for (cmd, desc) in commands {
        let _ = write!(out, "  \x1b[32m{:<16}\x1b[0m {}\r\n", cmd, desc);
    }
    let _ = write!(out, "\r\n");

    out
}
