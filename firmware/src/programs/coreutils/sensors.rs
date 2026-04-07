use alloc::string::String as AllocString;
use core::fmt::Write;

use crate::{config::topology::CURRENT_TOPOLOGY, state};

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let co2 = state::co2_reading();

    let _ = write!(out, "\r\n");

    // Connected sensors from topology
    for sensor in CURRENT_TOPOLOGY.enabled_sensors() {
        let mut line = AllocString::new();
        let _ = write!(line, "\x1b[1m{}\x1b[0m", sensor.model);

        match sensor.kind {
            crate::config::topology::SensorKind::Scd30
            | crate::config::topology::SensorKind::Scd4x => {
                if co2.ok {
                    let _ = write!(
                        line,
                        "  co2=\x1b[1;32m{:.1}\x1b[0m ppm  temp=\x1b[1;33m{:.1}\x1b[0m\u{00b0}C  rh=\x1b[1;36m{:.1}\x1b[0m%%",
                        co2.co2_ppm, co2.temperature, co2.humidity
                    );
                } else {
                    let _ = write!(line, "  \x1b[2mwaiting for data\x1b[0m");
                }
            }
            _ => {
                let _ = write!(line, "  \x1b[2mno live data\x1b[0m");
            }
        }

        // Bus info
        let _ = write!(line, "  \x1b[2m({}", sensor.bus_label);
        if let Some(addr) = sensor.i2c_address {
            let _ = write!(line, " @ 0x{:02X}", addr);
        }
        let _ = write!(line, ")\x1b[0m");

        let _ = write!(
            out,
            "  \x1b[33m{:<20}\x1b[0m {}\r\n",
            sensor.name, line
        );
    }

    let _ = write!(out, "\r\n");

    // Bus topology
    for bus in CURRENT_TOPOLOGY.buses {
        if let Some((sda, scl)) = bus.i2c_pins() {
            let _ = write!(
                out,
                "  \x1b[33m{:<20}\x1b[0m SDA:\x1b[1mGPIO{}\x1b[0m  SCL:\x1b[1mGPIO{}\x1b[0m\r\n",
                bus.label, sda, scl
            );
        }
    }

    let _ = write!(out, "\r\n");
    out
}
