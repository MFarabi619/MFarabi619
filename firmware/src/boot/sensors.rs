use embassy_executor::Spawner;
use esp_hal::i2c::master::I2c;

use crate::sensors;

pub fn spawn_sensor_tasks(
    spawner: &Spawner,
    i2c0_bus: &mut Option<I2c<'static, esp_hal::Async>>,
    i2c1_bus: &mut Option<I2c<'static, esp_hal::Async>>,
) {
    sensors::manager::spawn_tasks(spawner, i2c0_bus, i2c1_bus)
}
