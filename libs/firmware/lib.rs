#![no_std]
#![allow(unexpected_cfgs)]

extern crate alloc;

pub mod programs;
pub mod services;

#[cfg(CONFIG_NETWORKING)]
pub mod networking;


// BDD narration helpers for ztest test bodies. Each emits a tagged, colored
// line via printk. Visual style matches the ceratina PlatformIO renderer:
// GIVEN cyan, WHEN yellow, THEN/AND magenta, with progressive indentation.
#[cfg(CONFIG_ZTEST)]
pub mod bdd {
    use alloc::ffi::CString;
    use core::ffi::c_char;

    extern "C" {
        fn printk(format: *const c_char, ...);
    }

    pub fn given(text: &str) {
        emit(text, c"  \x1b[1;30;46m[GIVEN]\x1b[0m \x1b[36m%s\x1b[0m\n".as_ptr());
    }

    pub fn when(text: &str) {
        emit(text, c"    \x1b[1;30;103m[WHEN]\x1b[0m \x1b[33m%s\x1b[0m\n".as_ptr());
    }

    pub fn then(text: &str) {
        emit(text, c"      \x1b[1;30;105m[THEN]\x1b[0m \x1b[35m%s\x1b[0m\n".as_ptr());
    }

    pub fn and(text: &str) {
        emit(text, c"      \x1b[1;30;105m[AND]\x1b[0m  \x1b[35m%s\x1b[0m\n".as_ptr());
    }

    fn emit(text: &str, format: *const c_char) {
        if let Ok(c_text) = CString::new(text) {
            unsafe { printk(format, c_text.as_ptr()) };
        }
    }
}
