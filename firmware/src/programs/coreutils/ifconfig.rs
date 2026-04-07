use core::fmt::Write;
use alloc::string::String as AllocString;
use esp_hal::efuse;
use crate::state;

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let info = state::device_info();
    let mac = efuse::base_mac_address();

    let _ = write!(out, "\r\n");
    let _ = write!(out, "  \x1b[33m{:<12}\x1b[0m {}.{}.{}.{}/24\r\n",
        "IPv4", info.ip_address[0], info.ip_address[1],
        info.ip_address[2], info.ip_address[3]);
    let _ = write!(out, "  \x1b[33m{:<12}\x1b[0m {:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}\r\n",
        "MAC", mac.as_bytes()[0], mac.as_bytes()[1], mac.as_bytes()[2],
        mac.as_bytes()[3], mac.as_bytes()[4], mac.as_bytes()[5]);
    let _ = write!(out, "\r\n");

    out
}
