use embassy_executor::Spawner;
use esp_hal::i2c::master::I2c;

use crate::config::I2CSensorKind;

pub const MAX_SENSOR_COUNT: usize =
    crate::config::i2c_topology::DEVICES.len() + crate::config::modbus_topology::DEVICES.len();

#[derive(Clone, Copy)]
pub enum TransportSnapshot {
    I2c {
        bus_index: u8,
        address: u8,
        mux_channel: i8,
    },
    Modbus {
        channel: u8,
        slave_id: u8,
        register_address: u16,
    },
}

#[derive(Clone, Copy)]
pub struct TransportSummary {
    pub bus_name: &'static str,
    pub bus_index: Option<u8>,
    pub channel: Option<u8>,
    pub address: Option<u8>,
    pub mux_channel: Option<i8>,
    pub slave_id: Option<u8>,
    pub register_address: Option<u16>,
}

impl TransportSnapshot {
    pub fn summary(self) -> TransportSummary {
        match self {
            Self::I2c {
                bus_index,
                address,
                mux_channel,
            } => TransportSummary {
                bus_name: match bus_index {
                    0 => "i2c.0",
                    1 => "i2c.1",
                    _ => "i2c.?",
                },
                bus_index: Some(bus_index),
                channel: None,
                address: Some(address),
                mux_channel: (mux_channel >= 0).then_some(mux_channel),
                slave_id: None,
                register_address: None,
            },
            Self::Modbus {
                channel,
                slave_id,
                register_address,
            } => TransportSummary {
                bus_name: match channel {
                    0 => "rs485.0",
                    1 => "rs485.1",
                    _ => "rs485.?",
                },
                bus_index: None,
                channel: Some(channel),
                address: None,
                mux_channel: None,
                slave_id: Some(slave_id),
                register_address: Some(register_address),
            },
        }
    }
}

#[derive(Clone, Copy)]
pub enum LiveReading {
    None,
    Co2(Co2Reading),
    TemperatureHumidity(TemperatureHumidityReading),
}

#[derive(Clone, Copy)]
pub struct SensorSnapshot {
    pub name: &'static str,
    pub model: &'static str,
    pub transport: TransportSnapshot,
    pub live: LiveReading,
}

impl SensorSnapshot {
    pub fn transport_summary(self) -> TransportSummary {
        self.transport.summary()
    }

    pub fn carbon_dioxide_reading(self) -> Option<Co2Reading> {
        match self.live {
            LiveReading::Co2(reading) => Some(reading),
            _ => None,
        }
    }

    pub fn temperature_humidity_reading(self) -> Option<TemperatureHumidityReading> {
        match self.live {
            LiveReading::TemperatureHumidity(reading) => Some(reading),
            _ => None,
        }
    }
}

pub struct StatusSnapshot {
    pub carbon_dioxide: Co2Reading,
    pub inventory: heapless::Vec<SensorSnapshot, MAX_SENSOR_COUNT>,
}

#[derive(Clone, Copy)]
pub struct Co2Reading {
    pub ok: bool,
    pub co2_ppm: f32,
    pub temperature: f32,
    pub humidity: f32,
    pub model: &'static str,
    pub name: &'static str,
}

impl Default for Co2Reading {
    fn default() -> Self {
        Self {
            ok: false,
            co2_ppm: 0.0,
            temperature: 0.0,
            humidity: 0.0,
            model: "unknown",
            name: "unknown",
        }
    }
}

static CO2_READING: critical_section::Mutex<core::cell::RefCell<Option<Co2Reading>>> =
    critical_section::Mutex::new(core::cell::RefCell::new(None));

pub fn publish_carbon_dioxide_reading(reading: Co2Reading) {
    critical_section::with(|cs| {
        CO2_READING.borrow_ref_mut(cs).replace(reading);
    });
}

#[derive(Clone, Copy)]
pub struct TemperatureHumidityReading {
    pub ok: bool,
    pub temperature_celsius: f32,
    pub relative_humidity_percent: f32,
    pub model: &'static str,
    pub name: &'static str,
}

impl Default for TemperatureHumidityReading {
    fn default() -> Self {
        Self {
            ok: false,
            temperature_celsius: 0.0,
            relative_humidity_percent: 0.0,
            model: "unknown",
            name: "unknown",
        }
    }
}

static TEMPERATURE_HUMIDITY_READINGS: critical_section::Mutex<
    core::cell::RefCell<
        [Option<TemperatureHumidityReading>;
            crate::config::temperature_humidity::MAX_SENSORS as usize],
    >,
> = critical_section::Mutex::new(core::cell::RefCell::new(
    [None; crate::config::temperature_humidity::MAX_SENSORS as usize],
));

pub fn publish_temperature_humidity_reading(index: usize, reading: TemperatureHumidityReading) {
    critical_section::with(|cs| {
        if let Some(slot) = TEMPERATURE_HUMIDITY_READINGS
            .borrow_ref_mut(cs)
            .get_mut(index)
        {
            *slot = Some(reading);
        }
    });
}

pub fn mark_temperature_humidity_unavailable(index: usize) {
    critical_section::with(|cs| {
        if let Some(slot) = TEMPERATURE_HUMIDITY_READINGS
            .borrow_ref_mut(cs)
            .get_mut(index)
        {
            *slot = None;
        }
    });
}

pub fn temperature_humidity_reading(index: usize) -> TemperatureHumidityReading {
    critical_section::with(|cs| {
        TEMPERATURE_HUMIDITY_READINGS
            .borrow_ref(cs)
            .get(index)
            .and_then(|slot| *slot)
            .unwrap_or_default()
    })
}

fn build_inventory_snapshot(
    carbon_dioxide: Co2Reading,
) -> heapless::Vec<SensorSnapshot, MAX_SENSOR_COUNT> {
    let mut sensors = heapless::Vec::new();
    let mut temperature_humidity_index = 0usize;

    for sensor in crate::config::i2c_topology::DEVICES {
        let live = match sensor.kind {
            I2CSensorKind::TemperatureHumidity => {
                let reading = temperature_humidity_reading(temperature_humidity_index);
                temperature_humidity_index += 1;
                LiveReading::TemperatureHumidity(reading)
            }
            I2CSensorKind::CarbonDioxideScd30 | I2CSensorKind::CarbonDioxideScd4x => {
                LiveReading::Co2(carbon_dioxide)
            }
            _ => LiveReading::None,
        };

        let _ = sensors.push(SensorSnapshot {
            name: sensor.name,
            model: sensor.model,
            transport: TransportSnapshot::I2c {
                bus_index: sensor.bus_index,
                address: sensor.address,
                mux_channel: sensor.mux_channel,
            },
            live,
        });
    }

    for sensor in crate::config::modbus_topology::DEVICES {
        let _ = sensors.push(SensorSnapshot {
            name: sensor.name,
            model: sensor.model,
            transport: TransportSnapshot::Modbus {
                channel: sensor.channel,
                slave_id: sensor.slave_id,
                register_address: sensor.register_address,
            },
            live: LiveReading::None,
        });
    }

    sensors
}

pub fn snapshot() -> StatusSnapshot {
    let carbon_dioxide = co2_reading();

    StatusSnapshot {
        inventory: build_inventory_snapshot(carbon_dioxide),
        carbon_dioxide,
    }
}

pub fn first_i2c_sensor_of_kind(kind: I2CSensorKind) -> Option<crate::config::I2CSensorConfig> {
    crate::config::i2c_topology::first_device_of_kind(kind).copied()
}

pub fn carbon_dioxide_address(kind: I2CSensorKind) -> u8 {
    first_i2c_sensor_of_kind(kind)
        .map(|sensor| sensor.address)
        .unwrap_or(match kind {
            I2CSensorKind::CarbonDioxideScd30 => 0x61,
            I2CSensorKind::CarbonDioxideScd4x => 0x62,
            _ => 0x00,
        })
}

pub fn carbon_dioxide_name() -> &'static str {
    first_i2c_sensor_of_kind(I2CSensorKind::CarbonDioxideScd30)
        .or_else(|| first_i2c_sensor_of_kind(I2CSensorKind::CarbonDioxideScd4x))
        .map(|sensor| sensor.name)
        .unwrap_or("carbon_dioxide_0")
}

pub fn carbon_dioxide_model(kind: I2CSensorKind) -> &'static str {
    first_i2c_sensor_of_kind(kind)
        .map(|sensor| sensor.model)
        .unwrap_or(match kind {
            I2CSensorKind::CarbonDioxideScd30 => "SCD30",
            I2CSensorKind::CarbonDioxideScd4x => "SCD4x",
            _ => "unknown",
        })
}

pub fn co2_reading() -> Co2Reading {
    critical_section::with(|cs| {
        CO2_READING
            .borrow_ref(cs)
            .as_ref()
            .copied()
            .unwrap_or_default()
    })
}

pub fn spawn_tasks(
    spawner: &Spawner,
    i2c0_bus: &mut Option<I2c<'static, esp_hal::Async>>,
    i2c1_bus: &mut Option<I2c<'static, esp_hal::Async>>,
) {
    let mut temperature_humidity_index = 0usize;

    for sensor in crate::config::i2c_topology::DEVICES {
        let i2c_bus = match sensor.bus_index {
            0 => i2c0_bus.take(),
            1 => i2c1_bus.take(),
            _ => None,
        };

        let Some(i2c_bus) = i2c_bus else {
            defmt::info!(
                "sensor {}: I2C bus {} not available",
                sensor.name,
                sensor.bus_index
            );
            continue;
        };

        match sensor.kind {
            I2CSensorKind::TemperatureHumidity => {
                spawner.spawn(
                    crate::programs::temperature_and_humidity::task(
                        i2c_bus,
                        sensor.address,
                        temperature_humidity_index,
                        sensor.name,
                    )
                    .unwrap(),
                );
                temperature_humidity_index += 1;
            }
            I2CSensorKind::CarbonDioxideScd30 | I2CSensorKind::CarbonDioxideScd4x => {
                spawner.spawn(crate::programs::carbon_dioxide::task(i2c_bus).unwrap());
            }
            _ => {
                defmt::info!("sensor {}: kind not yet implemented", sensor.name);
            }
        }
    }
}
