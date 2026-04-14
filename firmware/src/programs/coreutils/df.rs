use alloc::string::String as AllocString;
use core::fmt::Write;

use crate::{config, services::system};

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let info = system::snapshot();

    let _ = write!(out, "\r\n");
    let _ = write!(
        out,
        "  \x1b[33m{:<16}\x1b[0m {:<12} {:<12} {:<8}\r\n",
        "Filesystem", "Size", "Type", "Mount"
    );

    if info.storage.sd_card_size_mb > 0 {
        let mut size = AllocString::new();
        if info.storage.sd_card_size_mb >= 1024 {
            let _ = write!(
                size,
                "{:.1} GiB",
                info.storage.sd_card_size_mb as f32 / 1024.0
            );
        } else {
            let _ = write!(size, "{} MiB", info.storage.sd_card_size_mb);
        }
        let _ = write!(
            out,
            "  \x1b[33m{:<16}\x1b[0m {:<12} {:<12} {:<8}\r\n",
            config::sd_card::DEVICE,
            size,
            config::sd_card::FS_TYPE,
            "/"
        );
    } else {
        let _ = write!(out, "  \x1b[2mno storage detected\x1b[0m\r\n");
    }

    let _ = write!(out, "\r\n");
    out
}
