use core::ffi::{c_char, CStr};

unsafe extern "C" {
    fn net_hostname_get() -> *const u8;
}

pub fn hostname() -> &'static str {
    unsafe { CStr::from_ptr(net_hostname_get().cast::<c_char>()) }
        .to_str()
        .unwrap_or("")
}

pub unsafe fn c_str_to_bytes<'a>(pointer: *const u8) -> &'a [u8] {
    if pointer.is_null() {
        return b"";
    }
    unsafe { CStr::from_ptr(pointer.cast::<c_char>()) }.to_bytes()
}
