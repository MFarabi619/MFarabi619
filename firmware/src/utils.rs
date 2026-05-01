unsafe extern "C" {
    fn net_hostname_get() -> *const u8;
}

pub fn hostname() -> &'static str {
    unsafe {
        let pointer = net_hostname_get();
        let mut length = 0;
        while *pointer.add(length) != 0 {
            length += 1;
        }
        core::str::from_utf8(core::slice::from_raw_parts(pointer, length)).unwrap_or("")
    }
}

pub unsafe fn c_str_to_bytes<'a>(pointer: *const u8) -> &'a [u8] {
    if pointer.is_null() {
        return b"";
    }
    let mut length = 0;
    unsafe {
        while *pointer.add(length) != 0 {
            length += 1;
        }
        core::slice::from_raw_parts(pointer, length)
    }
}
