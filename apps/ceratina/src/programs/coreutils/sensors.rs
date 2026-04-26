use alloc::string::String as AllocString;
use core::fmt::Write;

use crate::{hardware, services::system};

pub fn run() -> AllocString {
    let mut out = AllocString::new();
    let snapshot = system::snapshot();
    let i2c_status = hardware::i2c::snapshot();

    let _ = write!(out, "\r\n");

    for sensor in snapshot.sensors.inventory.iter() {
        let mut line = AllocString::new();
        let transport = sensor.transport_summary();
        let _ = write!(line, "\x1b[1m{}\x1b[0m", sensor.model);

        if let Some(reading) = sensor.carbon_dioxide_reading() {
            if reading.ok {
                let _ = write!(
                    line,
                    "  co2=\x1b[1;32m{:.1}\x1b[0m ppm  temp=\x1b[1;33m{:.1}\x1b[0m\u{00b0}C  rh=\x1b[1;36m{:.1}\x1b[0m%%",
                    reading.co2_ppm, reading.temperature, reading.humidity
                );
            } else {
                let _ = write!(line, "  \x1b[2mwaiting for data\x1b[0m");
            }
        } else if let Some(reading) = sensor.temperature_humidity_reading() {
            if reading.ok {
                let _ = write!(
                    line,
                    "  temp=\x1b[1;33m{:.1}\x1b[0m C  rh=\x1b[1;36m{:.1}\x1b[0m%%",
                    reading.temperature_celsius, reading.relative_humidity_percent
                );
            } else {
                let _ = write!(line, "  \x1b[2mwaiting for data\x1b[0m");
            }
        } else {
            let _ = write!(line, "  \x1b[2mno live data\x1b[0m");
        }

        if let Some(address) = transport.address {
            let _ = write!(line, "  \x1b[2m({} @ 0x{:02X}", transport.bus_name, address);
            if let Some(mux_channel) = transport.mux_channel {
                let _ = write!(line, " mux:{}", mux_channel);
            }
            let _ = write!(line, ")\x1b[0m");
        } else {
            let _ = write!(
                line,
                "  \x1b[2m({} slave {} reg {})\x1b[0m",
                transport.bus_name,
                transport.slave_id.unwrap_or_default(),
                transport.register_address.unwrap_or_default()
            );
        }

        let _ = write!(out, "  \x1b[33m{:<20}\x1b[0m {}\r\n", sensor.name, line);
    }

    let _ = write!(out, "\r\n");

    for bus in i2c_status.buses.iter() {
        let _ = write!(
            out,
            "  \x1b[33m{:<20}\x1b[0m SDA:\x1b[1mGPIO{}\x1b[0m  SCL:\x1b[1mGPIO{}\x1b[0m\r\n",
            bus.name, bus.sda_gpio, bus.scl_gpio
        );
    }

    if i2c_status.discovered_devices.is_empty() {
        let _ = write!(
            out,
            "  \x1b[33m{:<20}\x1b[0m \x1b[2mnone detected\x1b[0m\r\n",
            "i2c.discovery"
        );
    } else {
        for discovered_device in i2c_status.discovered_devices.iter() {
            let _ = write!(
                out,
                "  \x1b[33m{:<20}\x1b[0m {} @ \x1b[1m0x{:02X}\x1b[0m\r\n",
                "i2c.discovery",
                discovered_device.bus_name(),
                discovered_device.address
            );
        }
    }

    let _ = write!(out, "\r\n");
    out
}
