use core::fmt::Write;
use alloc::string::String as AllocString;
use crate::filesystems::sd::{copy_file, delete_file};

pub fn run(args: &str) -> AllocString {
    let parts: heapless::Vec<&str, 2> = args.splitn(2, ' ').collect();
    if parts.len() < 2 {
        return super::fmt_usage("mv <src> <dst>");
    }

    let src = parts[0].trim();
    let dst = parts[1].trim();

    match copy_file(src, dst) {
        Ok(bytes) => match delete_file(src) {
            Ok(()) => {
                let mut out = AllocString::new();
                let _ = write!(out, "moved {} -> {} ({} bytes)\r\n", src, dst, bytes);
                out
            }
            Err(error) => super::fmt_error(&error),
        },
        Err(error) => super::fmt_error(&error),
    }
}
