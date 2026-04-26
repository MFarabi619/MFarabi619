//! Hardware configuration — changes per PCB revision.
//!
//! GPIO pins, I2C bus layout, sensor topology, RS485 buses,
//! SD card SPI pins, button GPIOs, LED GPIO.

pub const PLATFORM: &str = "esp32s3";

pub mod led {
    pub const GPIO: u8 = 38;
    pub const COUNT: u8 = 1;
}

pub mod i2c {
    pub struct BusConfig {
        pub sda_gpio: u8,
        pub scl_gpio: u8,
    }
    pub const FREQUENCY_KHZ: u32 = 100;
    pub const LEGACY_POWER_GPIO: u8 = 5;
    pub const BUS_0: BusConfig = BusConfig {
        sda_gpio: 8,
        scl_gpio: 9,
    };
    pub const BUS_1: BusConfig = BusConfig {
        sda_gpio: 17,
        scl_gpio: 18,
    };
    pub const MUX_ADDR: u8 = 0x70;
    pub const DIRECT_CHANNEL: i8 = -1;
    pub const ANY_MUX_CHANNEL: i8 = -2;
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum I2CSensorKind {
    TemperatureHumidityCHT832X,
    TemperatureHumiditySHT3X,
    VoltageADS1115,
    CurrentINA228,
    CarbonDioxideSCD30,
    CarbonDioxideSCD4X,
    RtcDS3231,
    EepromAT24C32,
}

#[derive(Clone, Copy)]
pub struct I2CSensorConfig {
    pub name: &'static str,
    pub model: &'static str,
    pub kind: I2CSensorKind,
    pub bus_index: u8,
    pub address: u8,
    pub mux_channel: i8,
}

pub mod i2c_topology {
    use super::{I2CSensorConfig, I2CSensorKind};

    pub const DEVICES: &[I2CSensorConfig] = &[
        I2CSensorConfig {
            name: "ds3231_0",
            model: "DS3231",
            kind: I2CSensorKind::RtcDS3231,
            bus_index: 0,
            address: 0x68,
            mux_channel: super::i2c::DIRECT_CHANNEL,
        },
        I2CSensorConfig {
            name: "eeprom_0",
            model: "AT24C32",
            kind: I2CSensorKind::EepromAT24C32,
            bus_index: 1,
            address: 0x50,
            mux_channel: super::i2c::DIRECT_CHANNEL,
        },
        I2CSensorConfig {
            name: "voltage_0",
            model: "ADS1115",
            kind: I2CSensorKind::VoltageADS1115,
            bus_index: 1,
            address: 0x48,
            mux_channel: super::i2c::ANY_MUX_CHANNEL,
        },
        I2CSensorConfig {
            name: "scd30_0",
            model: "SCD30",
            kind: I2CSensorKind::CarbonDioxideSCD30,
            bus_index: 1,
            address: 0x61,
            mux_channel: super::i2c::DIRECT_CHANNEL,
        },
        I2CSensorConfig {
            name: "scd4x_0",
            model: "SCD4x",
            kind: I2CSensorKind::CarbonDioxideSCD4X,
            bus_index: 1,
            address: 0x62,
            mux_channel: super::i2c::DIRECT_CHANNEL,
        },
        I2CSensorConfig {
            name: "temperature_and_humidity_mux",
            model: "CHT832X",
            kind: I2CSensorKind::TemperatureHumidityCHT832X,
            bus_index: 1,
            address: 0x44,
            mux_channel: super::i2c::ANY_MUX_CHANNEL,
        },
        I2CSensorConfig {
            name: "temperature_and_humidity_0",
            model: "SHT31",
            kind: I2CSensorKind::TemperatureHumiditySHT3X,
            bus_index: 0,
            address: 0x44,
            mux_channel: super::i2c::DIRECT_CHANNEL,
        },
        I2CSensorConfig {
            name: "temperature_and_humidity_1",
            model: "SHT31",
            kind: I2CSensorKind::TemperatureHumiditySHT3X,
            bus_index: 1,
            address: 0x44,
            mux_channel: super::i2c::DIRECT_CHANNEL,
        },
    ];

    pub fn find_by_address(address: u8) -> Option<&'static I2CSensorConfig> {
        DEVICES.iter().find(|d| d.address == address)
    }

    pub fn devices_of_kind(kind: I2CSensorKind) -> impl Iterator<Item = &'static I2CSensorConfig> {
        DEVICES.iter().filter(move |d| d.kind == kind)
    }

    pub fn first_device_of_kind(kind: I2CSensorKind) -> Option<&'static I2CSensorConfig> {
        devices_of_kind(kind).next()
    }
}

pub mod rs485 {
    pub struct BusConfig {
        pub tx_gpio: i8,
        pub rx_gpio: i8,
        pub de_re_gpio: i8,
        pub baud_rate: u32,
    }
    pub const CHANNEL_COUNT: u8 = 2;
    pub const BUS_0: BusConfig = BusConfig {
        tx_gpio: 45,
        rx_gpio: 48,
        de_re_gpio: 47,
        baud_rate: 9600,
    };
    pub const BUS_1: BusConfig = BusConfig {
        tx_gpio: 40,
        rx_gpio: 39,
        de_re_gpio: 41,
        baud_rate: 4800,
    };
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum ModbusSensorKind {
    WindSpeed,
    WindDirection,
    SolarRadiation,
    SoilProbe,
}

#[derive(Clone, Copy)]
pub struct ModbusSensorConfig {
    pub name: &'static str,
    pub model: &'static str,
    pub kind: ModbusSensorKind,
    pub channel: u8,
    pub slave_id: u8,
    pub register_address: u16,
}

pub mod modbus_topology {
    use super::{ModbusSensorConfig, ModbusSensorKind};

    pub const DEVICES: &[ModbusSensorConfig] = &[
        ModbusSensorConfig {
            name: "wind_speed_0",
            model: "DFRobot SEN0483",
            kind: ModbusSensorKind::WindSpeed,
            channel: 0,
            slave_id: 20,
            register_address: 0,
        },
        ModbusSensorConfig {
            name: "wind_direction_0",
            model: "DFRobot SEN0482",
            kind: ModbusSensorKind::WindDirection,
            channel: 0,
            slave_id: 30,
            register_address: 0,
        },
    ];

    pub fn find_by_kind(kind: ModbusSensorKind) -> Option<&'static ModbusSensorConfig> {
        DEVICES.iter().find(|d| d.kind == kind)
    }
}

pub mod sd_card {
    pub const CS_GPIO: u32 = 10;
    pub const MOSI_GPIO: u32 = 11;
    pub const SCK_GPIO: u32 = 12;
    pub const MISO_GPIO: u32 = 13;
    pub const SPI_INIT_FREQUENCY_KHZ: u32 = 400;
}

pub mod eeprom {
    pub const I2C_ADDR: u8 = 0x50;
    pub const PAGE_SIZE: u16 = 32;
    pub const TOTAL_SIZE: u16 = 4096;
}

pub mod temperature_humidity {
    pub const I2C_ADDR: u8 = 0x44;
    pub const SHT3X_RESET_GPIO_PIN: u8 = 4;
}

pub mod voltage {
    pub const I2C_ADDR: u8 = 0x48;
}

pub mod buttons {
    pub const GPIO_1: i8 = -1;
    pub const GPIO_2: i8 = 4;
    pub const GPIO_3: i8 = 42;
    pub const COUNT: u8 = 3;
}
