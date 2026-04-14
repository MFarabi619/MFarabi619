use esp_hal::i2c::master::{Config as I2cConfig, I2c};
use esp_hal::time::Rate;

use crate::config;

pub const SENSOR_CANDIDATE_ADDRESSES: [u8; 4] = [0x44, 0x45, 0x46, 0x47];
pub const SENSOR_MEASUREMENT_COMMAND: [u8; 2] = [0x24, 0x00];
pub const MAX_DISCOVERED_DEVICES: usize = 16;
const I2C_SCAN_ADDRESS_MIN: u8 = 0x08;
const I2C_SCAN_ADDRESS_MAX: u8 = 0x77;

#[derive(Clone, Copy)]
pub struct BusStatusSnapshot {
    pub name: &'static str,
    pub bus_index: u8,
    pub sda_gpio: u8,
    pub scl_gpio: u8,
}

#[derive(Clone, Copy)]
pub struct DiscoveredDeviceSnapshot {
    pub bus_index: u8,
    pub address: u8,
}

impl DiscoveredDeviceSnapshot {
    pub fn bus_name(self) -> &'static str {
        match self.bus_index {
            0 => "i2c.0",
            1 => "i2c.1",
            _ => "i2c.?",
        }
    }
}

pub struct I2cSnapshot {
    pub frequency_khz: u32,
    pub power_gpio: u8,
    pub buses: [BusStatusSnapshot; 2],
    pub discovered_devices: heapless::Vec<DiscoveredDeviceSnapshot, MAX_DISCOVERED_DEVICES>,
}

static DISCOVERED_DEVICES: critical_section::Mutex<
    core::cell::RefCell<heapless::Vec<DiscoveredDeviceSnapshot, MAX_DISCOVERED_DEVICES>>,
> = critical_section::Mutex::new(core::cell::RefCell::new(heapless::Vec::new()));

pub fn initialize_bus_0(
    peripheral: esp_hal::peripherals::I2C0<'static>,
    sda: esp_hal::peripherals::GPIO8<'static>,
    scl: esp_hal::peripherals::GPIO9<'static>,
) -> I2c<'static, esp_hal::Async> {
    I2c::new(
        peripheral,
        I2cConfig::default().with_frequency(Rate::from_khz(config::i2c::FREQUENCY_KHZ)),
    )
    .unwrap()
    .with_sda(sda)
    .with_scl(scl)
    .into_async()
}

pub fn initialize_bus_1(
    peripheral: esp_hal::peripherals::I2C1<'static>,
    sda: esp_hal::peripherals::GPIO17<'static>,
    scl: esp_hal::peripherals::GPIO18<'static>,
) -> I2c<'static, esp_hal::Async> {
    I2c::new(
        peripheral,
        I2cConfig::default().with_frequency(Rate::from_khz(config::i2c::FREQUENCY_KHZ)),
    )
    .unwrap()
    .with_sda(sda)
    .with_scl(scl)
    .into_async()
}

pub async fn refresh_discovery(
    i2c0_bus: &mut Option<I2c<'static, esp_hal::Async>>,
    i2c1_bus: &mut Option<I2c<'static, esp_hal::Async>>,
) -> usize {
    let mut discovered_devices = heapless::Vec::<DiscoveredDeviceSnapshot, MAX_DISCOVERED_DEVICES>::new();

    if let Some(i2c_bus) = i2c0_bus.as_mut() {
        discover_bus_devices(0, i2c_bus, &mut discovered_devices).await;
    }

    if let Some(i2c_bus) = i2c1_bus.as_mut() {
        discover_bus_devices(1, i2c_bus, &mut discovered_devices).await;
    }

    critical_section::with(|cs| {
        let mut cached_devices = DISCOVERED_DEVICES.borrow_ref_mut(cs);
        cached_devices.clear();
        for discovered_device in discovered_devices.iter() {
            let _ = cached_devices.push(*discovered_device);
        }
    });

    for discovered_device in discovered_devices.iter() {
        defmt::info!(
            "i2c discovery: found {=u8:#x} on bus {=u8}",
            discovered_device.address,
            discovered_device.bus_index
        );
    }

    discovered_devices.len()
}

pub fn snapshot() -> I2cSnapshot {
    let mut discovered_devices = heapless::Vec::new();

    critical_section::with(|cs| {
        for discovered_device in DISCOVERED_DEVICES.borrow_ref(cs).iter() {
            let _ = discovered_devices.push(*discovered_device);
        }
    });

    I2cSnapshot {
        frequency_khz: config::i2c::FREQUENCY_KHZ,
        power_gpio: config::i2c::LEGACY_POWER_GPIO,
        buses: [
            BusStatusSnapshot {
                name: "i2c.0",
                bus_index: 0,
                sda_gpio: config::i2c::BUS_0.sda_gpio,
                scl_gpio: config::i2c::BUS_0.scl_gpio,
            },
            BusStatusSnapshot {
                name: "i2c.1",
                bus_index: 1,
                sda_gpio: config::i2c::BUS_1.sda_gpio,
                scl_gpio: config::i2c::BUS_1.scl_gpio,
            },
        ],
        discovered_devices,
    }
}

pub async fn select_mux_channel(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
    mux_channel: u8,
) -> Result<(), &'static str> {
    if mux_channel > 7 {
        return Err("mux channel out of range");
    }

    let mux_channel_mask = 1_u8 << mux_channel;
    i2c_bus
        .write_async(config::i2c::MUX_ADDR, &[mux_channel_mask])
        .await
        .map_err(|_| "failed to select I2C mux channel")?;
    Ok(())
}

pub async fn discover_sensor_address(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
) -> Option<u8> {
    for sensor_candidate_address in SENSOR_CANDIDATE_ADDRESSES {
        if i2c_bus
            .write_async(sensor_candidate_address, &[])
            .await
            .is_ok()
        {
            return Some(sensor_candidate_address);
        }
    }

    None
}

async fn discover_bus_devices(
    bus_index: u8,
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
    discovered_devices: &mut heapless::Vec<DiscoveredDeviceSnapshot, MAX_DISCOVERED_DEVICES>,
) {
    for address in I2C_SCAN_ADDRESS_MIN..=I2C_SCAN_ADDRESS_MAX {
        if address == config::i2c::MUX_ADDR {
            continue;
        }

        if i2c_bus.write_async(address, &[]).await.is_ok() {
            let _ = discovered_devices.push(DiscoveredDeviceSnapshot { bus_index, address });
            if discovered_devices.is_full() {
                break;
            }
        }
    }
}

pub fn calculate_crc8(data_bytes: &[u8]) -> u8 {
    let mut crc_value: u8 = 0xFF;

    for data_byte in data_bytes {
        crc_value ^= *data_byte;
        for _ in 0..8 {
            crc_value = if (crc_value & 0x80) != 0 {
                (crc_value << 1) ^ 0x31
            } else {
                crc_value << 1
            };
        }
    }

    crc_value
}
