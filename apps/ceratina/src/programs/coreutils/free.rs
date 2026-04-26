use alloc::string::String as AllocString;
use core::fmt::Write;

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let used = esp_alloc::HEAP.used();
    let free = esp_alloc::HEAP.free();
    let total = used + free;
    let pct = if total > 0 { (used * 100) / total } else { 0 };

    let _ = write!(out, "\r\n");
    let _ = write!(
        out,
        "  \x1b[33m{:<12}\x1b[0m {:<12} {:<12} {:<12}\r\n",
        "", "total", "used", "free"
    );
    let _ = write!(
        out,
        "  \x1b[33m{:<12}\x1b[0m {:<12.1} {:<12.1} {:<12.1}\r\n",
        "Heap (KiB)",
        total as f32 / 1024.0,
        used as f32 / 1024.0,
        free as f32 / 1024.0,
    );
    let _ = write!(out, "  \x1b[33m{:<12}\x1b[0m {}%\r\n", "Usage", pct);
    let _ = write!(out, "\r\n");
    out
}
