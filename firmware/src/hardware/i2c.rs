use esp_hal::i2c::master::{Config as I2cConfig, I2c};
use esp_hal::time::Rate;

use crate::config::board;

pub const MAX_DISCOVERED_DEVICES: usize = 16;
pub const SENSOR_CANDIDATE_ADDRESSES: [u8; 4] = [0x44, 0x45, 0x46, 0x47];
pub const SENSOR_MEASUREMENT_COMMAND: [u8; 2] = [0x24, 0x00];
const I2C_SCAN_ADDRESS_MIN: u8 = 0x08;
const I2C_SCAN_ADDRESS_MAX: u8 = 0x77;

#[derive(Clone, Copy, defmt::Format)]
pub struct DiscoveredDevice {
    pub bus: u8,
    pub address: u8,
}

impl DiscoveredDevice {
    pub fn bus_name(self) -> &'static str {
        match self.bus {
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
    pub discovered_devices: heapless::Vec<DiscoveredDevice, MAX_DISCOVERED_DEVICES>,
}

#[derive(Clone, Copy)]
pub struct BusStatusSnapshot {
    pub name: &'static str,
    pub bus_index: u8,
    pub sda_gpio: u8,
    pub scl_gpio: u8,
}

static DISCOVERY_CACHE: critical_section::Mutex<
    core::cell::RefCell<heapless::Vec<DiscoveredDevice, MAX_DISCOVERED_DEVICES>>,
> = critical_section::Mutex::new(core::cell::RefCell::new(heapless::Vec::new()));

static DISCOVERY_DONE: core::sync::atomic::AtomicBool =
    core::sync::atomic::AtomicBool::new(false);

// ─────────────────────────────────────────────────────────────────────────────
//  Bus initialization
// ─────────────────────────────────────────────────────────────────────────────

pub fn initialize_bus_0(
    peripheral: esp_hal::peripherals::I2C0<'static>,
    sda: esp_hal::peripherals::GPIO8<'static>,
    scl: esp_hal::peripherals::GPIO9<'static>,
) -> I2c<'static, esp_hal::Async> {
    I2c::new(
        peripheral,
        I2cConfig::default().with_frequency(Rate::from_khz(board::i2c::FREQUENCY_KHZ)),
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
        I2cConfig::default().with_frequency(Rate::from_khz(board::i2c::FREQUENCY_KHZ)),
    )
    .unwrap()
    .with_sda(sda)
    .with_scl(scl)
    .into_async()
}

// ─────────────────────────────────────────────────────────────────────────────
//  Discovery — mirrors C++ hardware::i2c::discoverAll / runDiscovery / findDevice
// ─────────────────────────────────────────────────────────────────────────────

pub async fn discover_all(
    i2c0_bus: &mut Option<I2c<'static, esp_hal::Async>>,
    i2c1_bus: &mut Option<I2c<'static, esp_hal::Async>>,
) -> heapless::Vec<DiscoveredDevice, MAX_DISCOVERED_DEVICES> {
    let mut devices = heapless::Vec::new();

    if let Some(bus) = i2c0_bus.as_mut() {
        discover_bus_devices(0, bus, &mut devices).await;
    }

    if let Some(bus) = i2c1_bus.as_mut() {
        discover_bus_devices(1, bus, &mut devices).await;
    }

    devices
}

pub async fn run_discovery(
    i2c0_bus: &mut Option<I2c<'static, esp_hal::Async>>,
    i2c1_bus: &mut Option<I2c<'static, esp_hal::Async>>,
) -> usize {
    let devices = discover_all(i2c0_bus, i2c1_bus).await;
    let count = devices.len();

    for device in devices.iter() {
        defmt::info!(
            "[i2c] found {:#04x} on bus {=u8} — {}",
            device.address,
            device.bus,
            device_name_at(device.address)
        );
    }

    critical_section::with(|cs| {
        let mut cache = DISCOVERY_CACHE.borrow_ref_mut(cs);
        cache.clear();
        for device in devices.iter() {
            let _ = cache.push(*device);
        }
    });
    DISCOVERY_DONE.store(true, core::sync::atomic::Ordering::Release);

    count
}

pub fn find_device(address: u8) -> Option<DiscoveredDevice> {
    critical_section::with(|cs| {
        DISCOVERY_CACHE
            .borrow_ref(cs)
            .iter()
            .find(|d| d.address == address)
            .copied()
    })
}

pub fn device_count() -> usize {
    critical_section::with(|cs| DISCOVERY_CACHE.borrow_ref(cs).len())
}

pub fn is_discovery_done() -> bool {
    DISCOVERY_DONE.load(core::sync::atomic::Ordering::Acquire)
}

pub fn device_name_at(address: u8) -> &'static str {
    match address {
        0x40 => "Texas Instruments INA228 Current Monitor",
        0x44 => "Sensirion SHT3x Temperature & Humidity Sensor",
        0x48 => "Texas Instruments ADS1115 16-Bit ADC",
        0x50 => "Microchip Technology AT24C32 EEPROM",
        0x5C | 0x5D => "Adafruit LPS25 Pressure Sensor",
        0x61 => "Sensirion SCD30 CO2 Infrared Gas Sensor",
        0x62 => "Sensirion SCD41 CO2 Optical Gas Sensor",
        0x68 => "Analog Devices DS3231 RTC",
        0x70 => "Adafruit TCA9548A I2C Multiplexer",
        _ => "unknown",
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Snapshot
// ─────────────────────────────────────────────────────────────────────────────

pub fn snapshot() -> I2cSnapshot {
    let mut discovered_devices = heapless::Vec::new();

    critical_section::with(|cs| {
        for device in DISCOVERY_CACHE.borrow_ref(cs).iter() {
            let _ = discovered_devices.push(*device);
        }
    });

    I2cSnapshot {
        frequency_khz: board::i2c::FREQUENCY_KHZ,
        power_gpio: board::i2c::LEGACY_POWER_GPIO,
        buses: [
            BusStatusSnapshot {
                name: "i2c.0",
                bus_index: 0,
                sda_gpio: board::i2c::BUS_0.sda_gpio,
                scl_gpio: board::i2c::BUS_0.scl_gpio,
            },
            BusStatusSnapshot {
                name: "i2c.1",
                bus_index: 1,
                sda_gpio: board::i2c::BUS_1.sda_gpio,
                scl_gpio: board::i2c::BUS_1.scl_gpio,
            },
        ],
        discovered_devices,
    }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Mux helpers
// ─────────────────────────────────────────────────────────────────────────────

pub async fn select_mux_channel(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
    mux_channel: u8,
) -> Result<(), &'static str> {
    if mux_channel > 7 {
        return Err("mux channel out of range");
    }

    let mux_channel_mask = 1_u8 << mux_channel;
    i2c_bus
        .write_async(board::i2c::MUX_ADDR, &[mux_channel_mask])
        .await
        .map_err(|_| "failed to select I2C mux channel")?;
    Ok(())
}

pub async fn clear_selection(
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
) -> Result<(), &'static str> {
    i2c_bus
        .write_async(board::i2c::MUX_ADDR, &[0x00])
        .await
        .map_err(|_| "failed to clear I2C mux selection")?;
    Ok(())
}

// ─────────────────────────────────────────────────────────────────────────────
//  Utilities
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
//  Internal
// ─────────────────────────────────────────────────────────────────────────────

async fn discover_bus_devices(
    bus_index: u8,
    i2c_bus: &mut I2c<'static, esp_hal::Async>,
    devices: &mut heapless::Vec<DiscoveredDevice, MAX_DISCOVERED_DEVICES>,
) {
    for address in I2C_SCAN_ADDRESS_MIN..=I2C_SCAN_ADDRESS_MAX {
        if address == board::i2c::MUX_ADDR {
            continue;
        }

        if i2c_bus.write_async(address, &[]).await.is_ok() {
            let _ = devices.push(DiscoveredDevice {
                bus: bus_index,
                address,
            });
            if devices.is_full() {
                break;
            }
        }
    }
}
