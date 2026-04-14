//! DS3231 real-time clock tasks.

use defmt::info;
use ds323x::{DateTimeAccess, Datelike, Ds323x, NaiveDateTime, Timelike};
use esp_hal::i2c::master::I2c;

use crate::common::setup::Device;

fn ds3231_i2c_address() -> u8 {
    0x68
}

fn ds3231_is_present_on_bus(i2c_bus: &mut I2c<'_, esp_hal::Blocking>) -> bool {
    i2c_bus.write(ds3231_i2c_address(), &[]).is_ok()
}

/// Identify which I2C bus the DS3231 is wired to. Returns `Ok("i2c.0")`,
/// `Ok("i2c.1")`, or `Err(...)` when the device doesn't ACK on either.
pub fn locate_bus(device: &mut Device) -> Result<&'static str, &'static str> {
    info!(
        "user probes both I2C buses for DS3231 at address=0x{=u8:02x}",
        ds3231_i2c_address()
    );

    if let Some(bus) = device.i2c_bus_0.as_mut()
        && ds3231_is_present_on_bus(bus)
    {
        info!("DS3231 found on bus=i2c.0");
        return Ok("i2c.0");
    }
    if let Some(bus) = device.i2c_bus_1.as_mut()
        && ds3231_is_present_on_bus(bus)
    {
        info!("DS3231 found on bus=i2c.1");
        return Ok("i2c.1");
    }
    Err("device: DS3231 did not ACK on either I2C bus")
}

/// Read the current datetime from the DS3231, whichever bus it is
/// wired to. The chosen bus is temporarily moved into the `Ds323x`
/// driver and returned to `Device` after the read completes, so later
/// tasks on the same device can still use the bus.
pub fn read_current_datetime(
    device: &mut Device,
) -> Result<NaiveDateTime, &'static str> {
    let bus_label = locate_bus(device)?;
    info!(
        "user reads the current datetime from the DS3231 on bus={=str}",
        bus_label
    );

    let borrowed_bus = match bus_label {
        "i2c.0" => device.i2c_bus_0.take(),
        "i2c.1" => device.i2c_bus_1.take(),
        _ => None,
    }
    .ok_or("device: I2C bus slot empty after locate")?;

    let mut rtc_driver = Ds323x::new_ds3231(borrowed_bus);
    let datetime_read_result = rtc_driver.datetime();
    let returned_bus = rtc_driver.destroy_ds3231();

    match bus_label {
        "i2c.0" => device.i2c_bus_0 = Some(returned_bus),
        "i2c.1" => device.i2c_bus_1 = Some(returned_bus),
        _ => {}
    }

    let current_datetime = datetime_read_result
        .map_err(|_| "device: DS3231 refused datetime read (check battery + wiring)")?;

    info!(
        "DS3231 reports year={=i32} month={=u32} day={=u32} hour={=u32} minute={=u32} second={=u32}",
        current_datetime.year(),
        current_datetime.month(),
        current_datetime.day(),
        current_datetime.hour(),
        current_datetime.minute(),
        current_datetime.second(),
    );
    Ok(current_datetime)
}
