use crate::services::system;
use alloc::string::String as AllocString;
use core::fmt::Write;
use esp_hal::efuse;

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let info = system::snapshot();
    let mac = efuse::base_mac_address();

    let _ = write!(out, "\r\n");
    let _ = write!(
        out,
        "  \x1b[33m{:<12}\x1b[0m {}\r\n",
        "STA",
        if info.network.station.is_connected {
            "\x1b[32mconnected\x1b[0m"
        } else {
            "\x1b[31mdisconnected\x1b[0m"
        }
    );
    let _ = write!(
        out,
        "  \x1b[33m{:<12}\x1b[0m {}.{}.{}.{}/24\r\n",
        "IPv4",
        info.network.station.ipv4_address[0],
        info.network.station.ipv4_address[1],
        info.network.station.ipv4_address[2],
        info.network.station.ipv4_address[3]
    );
    let _ = write!(
        out,
        "  \x1b[33m{:<12}\x1b[0m {:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}\r\n",
        "MAC",
        mac.as_bytes()[0],
        mac.as_bytes()[1],
        mac.as_bytes()[2],
        mac.as_bytes()[3],
        mac.as_bytes()[4],
        mac.as_bytes()[5]
    );
    let _ = write!(
        out,
        "  \x1b[33m{:<12}\x1b[0m {} (ch {}, {}, fallback={})\r\n",
        "AP",
        info.network.access_point.ssid,
        info.network.access_point.channel,
        info.network.access_point.auth_mode,
        if info.network.access_point.fallback_enabled {
            "yes"
        } else {
            "no"
        }
    );
    let _ = write!(out, "\r\n");

    out
}
