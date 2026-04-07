use core::fmt::Write;
use alloc::string::String as AllocString;
use crate::filesystems::sd::read_file_at;

pub fn run(cwd: &str, name: &str) -> AllocString {
    if name.is_empty() {
        return super::fmt_usage("cat <filename>");
    }

    match read_file_at::<8192>(cwd, name) {
        Ok(contents) => {
            let mut out = AllocString::new();
            match core::str::from_utf8(contents.as_slice()) {
                Ok(text) => {
                    for line in text.lines() {
                        let _ = write!(out, "{}\r\n", line);
                    }
                }
                Err(_) => {
                    let _ = write!(out, "\x1b[2m({} bytes, binary)\x1b[0m\r\n", contents.len());
                }
            }
            out
        }
        Err(error) => super::fmt_error(&error),
    }
}
