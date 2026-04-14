use esp_hal::i2c::master::I2c;

pub fn initialize_i2c_buses(
    i2c0_peripheral: esp_hal::peripherals::I2C0<'static>,
    i2c1_peripheral: esp_hal::peripherals::I2C1<'static>,
    gpio8: esp_hal::peripherals::GPIO8<'static>,
    gpio9: esp_hal::peripherals::GPIO9<'static>,
    gpio17: esp_hal::peripherals::GPIO17<'static>,
    gpio18: esp_hal::peripherals::GPIO18<'static>,
) -> (
    Option<I2c<'static, esp_hal::Async>>,
    Option<I2c<'static, esp_hal::Async>>,
) {
    let i2c0_bus = Some(crate::hardware::i2c::initialize_bus_0(
        i2c0_peripheral,
        gpio8,
        gpio9,
    ));

    let i2c1_bus = Some(crate::hardware::i2c::initialize_bus_1(
        i2c1_peripheral,
        gpio17,
        gpio18,
    ));

    (i2c0_bus, i2c1_bus)
}

pub async fn discover_i2c_devices(
    i2c0_bus: &mut Option<I2c<'static, esp_hal::Async>>,
    i2c1_bus: &mut Option<I2c<'static, esp_hal::Async>>,
) -> usize {
    crate::hardware::i2c::run_discovery(i2c0_bus, i2c1_bus).await
}
