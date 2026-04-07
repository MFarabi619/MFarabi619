use alloc::string::String as AllocString;
use core::fmt::Write;

pub fn fmt_error(error: &impl core::fmt::Display) -> AllocString {
    let mut out = AllocString::new();
    let _ = write!(out, "\x1b[31merror: {}\x1b[0m\r\n", error);
    out
}

pub fn fmt_usage(usage: &str) -> AllocString {
    let mut out = AllocString::new();
    let _ = write!(out, "\x1b[31musage: {}\x1b[0m\r\n", usage);
    out
}

pub mod cat;
pub mod cp;
pub mod date;
pub mod df;
pub mod free;
pub mod help;
pub mod hostname;
pub mod ifconfig;
pub mod ls;
pub mod mkdir;
pub mod mv;
pub mod rm;
pub mod sensors;
pub mod touch;
pub mod uptime;
pub mod whoami;
