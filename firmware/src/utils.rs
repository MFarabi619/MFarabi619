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
        core::str::from_utf8_unchecked(core::slice::from_raw_parts(pointer, length))
    }
}
