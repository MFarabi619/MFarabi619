use comfy_table::{Attribute, Cell, Color, ContentArrangement, Table, modifiers, presets::UTF8_FULL};
use probe_rs::probe::list::Lister;
use serialport::SerialPortType;
use std::collections::HashMap;

fn main() {
    let probes_by_vid_pid_serial: HashMap<(u16, u16, Option<String>), String> = Lister::new()
        .list_all()
        .into_iter()
        .map(|p| ((p.vendor_id, p.product_id, p.serial_number), p.identifier))
        .collect();

    let mut table = Table::new();
    table
        .load_preset(UTF8_FULL)
        .apply_modifier(modifiers::UTF8_ROUND_CORNERS)
        .set_content_arrangement(ContentArrangement::Dynamic)
        .set_truncation_indicator("…")
        .set_header(
            [
                ("Serial", Color::Green),
                // ("Port", Color::Green),
                ("VID:PID", Color::Magenta),
                ("Debug Probe", Color::Blue),
                ("Manufacturer", Color::Yellow),
                // ("Product", Color::DarkCyan),
            ]
            .into_iter()
            .map(|(label, color)| Cell::new(label).fg(color).add_attribute(Attribute::Bold))
            .collect::<Vec<_>>(),
        );

    let ports = serialport::available_ports().unwrap_or_default();
    let mut count = 0;
    for port in ports {
        let SerialPortType::UsbPort(info) = port.port_type else { continue };
        let probe_name = probes_by_vid_pid_serial
            .get(&(info.vid, info.pid, info.serial_number.clone()))
            .cloned()
            .unwrap_or_default();
        if !probe_name.is_empty() && port.port_name.starts_with("/dev/tty.") {
            continue;
        }
        count += 1;
        table.add_row(vec![
            Cell::new(info.serial_number.unwrap_or_default()).fg(Color::Green),
            // Cell::new(&port.port_name).fg(Color::Green),
            Cell::new(format!("{:04x}:{:04x}", info.vid, info.pid)).fg(Color::Magenta),
            Cell::new(probe_name).fg(Color::Blue),
            Cell::new(info.manufacturer.unwrap_or_default()).fg(Color::Yellow),
            // Cell::new(info.product.unwrap_or_default()).fg(Color::DarkCyan),
        ]);
    }
    if count == 0 {
        table.add_row(vec![Cell::new("(none)").fg(Color::DarkGrey)]);
    }

    println!("{table}");
}
