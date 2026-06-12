use lazyzephyr_core::commands::probes::{ProbeInfo, ProbeRegistry};
use probe_rs::probe::list::Lister;
use serialport::{SerialPortType, available_ports};

pub struct ProbeRsRegistry {
    lister: Lister,
}

impl ProbeRsRegistry {
    pub fn new() -> Self {
        Self { lister: Lister::new() }
    }
}

impl ProbeRegistry for ProbeRsRegistry {
    fn list(&mut self) -> Vec<ProbeInfo> {
        let probes = self.lister.list_all();
        let usb_ports: Vec<_> = available_ports()
            .unwrap_or_default()
            .into_iter()
            .filter_map(|port| match port.port_type {
                SerialPortType::UsbPort(info) => Some((port.port_name, info)),
                _ => None,
            })
            .collect();

        probes
            .into_iter()
            .map(|probe| {
                let device_path = probe.serial_number.as_deref().and_then(|sn| {
                    usb_ports
                        .iter()
                        .find(|(_, info)| info.serial_number.as_deref() == Some(sn))
                        .map(|(name, _)| name.clone())
                });
                let probe_type = probe.probe_type();
                ProbeInfo {
                    identifier:    probe.identifier,
                    vendor_id:     probe.vendor_id,
                    product_id:    probe.product_id,
                    serial_number: probe.serial_number,
                    probe_type,
                    device_path,
                }
            })
            .collect()
    }
}
