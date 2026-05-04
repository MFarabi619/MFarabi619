use zephyr::raw::*;

// Channel indices must stay aligned with sensors/channels.h. Wind/rain channels
// are unused at runtime but kept reserved so re-enabling those sensors does
// not shift downstream constants. The `sensor_channel_SENSOR_CHAN_*` and
// `sensor_attribute_SENSOR_ATTR_*` symbols on the right-hand side are
// bindgen-generated from Zephyr headers — the doubled prefix is bindgen's
// enum namespacing, not ours, and cannot be shortened.
const SOIL_MOISTURE_CHANNEL: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 4;
const SOIL_CONDUCTIVITY_CHANNEL: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 5;
const SOIL_SALINITY_CHANNEL: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 6;
const SOIL_TDS_CHANNEL: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 7;

const SLAVE_ID_ATTRIBUTE: u32 = sensor_attribute_SENSOR_ATTR_PRIV_START + 1;

unsafe extern "C" {
    fn zr_sensor_get_soil_moisture() -> *const device;
    fn zr_sensor_get_soil_moisture_three_in_one() -> *const device;
    fn zr_sensor_get_co2() -> *const device;
    fn zr_sensor_init_co2() -> i32;
}

fn sensor_value_to_f32(value: &sensor_value) -> f32 {
    value.val1 as f32 + value.val2 as f32 / 1_000_000.0
}

fn get_channel(device: *const device, channel: u32) -> Option<f32> {
    if device.is_null() {
        return None;
    }

    unsafe {
        let mut value: sensor_value = core::mem::zeroed();
        if sensor_channel_get(device as *mut _, channel, &mut value) != 0 {
            return None;
        }

        Some(sensor_value_to_f32(&value))
    }
}

pub struct SoilProbe {
    pub device: *const device,
    pub has_extended_metrics: bool,
}

pub struct SoilReading {
    pub slave_id: u8,
    pub temperature_celsius: f32,
    pub moisture_percent: f32,
    pub conductivity: Option<u16>,
    pub salinity: Option<u16>,
    pub tds: Option<u16>,
}

pub fn read_soil(device: *const device) -> Option<SoilReading> {
    if device.is_null() {
        return None;
    }

    unsafe {
        if sensor_sample_fetch(device as *mut _) != 0 {
            return None;
        }
    }

    let moisture = get_channel(device, SOIL_MOISTURE_CHANNEL)?;
    let temperature = get_channel(device, sensor_channel_SENSOR_CHAN_AMBIENT_TEMP)?;

    let conductivity = get_channel(device, SOIL_CONDUCTIVITY_CHANNEL)
        .map(|value| value as u16);
    let salinity = get_channel(device, SOIL_SALINITY_CHANNEL)
        .map(|value| value as u16);
    let tds = get_channel(device, SOIL_TDS_CHANNEL)
        .map(|value| value as u16);

    let mut slave_value: sensor_value = unsafe { core::mem::zeroed() };
    let slave_id = unsafe {
        if sensor_attr_get(
            device as *mut _,
            0,
            SLAVE_ID_ATTRIBUTE,
            &mut slave_value,
        ) == 0
        {
            slave_value.val1 as u8
        } else {
            0
        }
    };

    Some(SoilReading {
        slave_id,
        temperature_celsius: temperature,
        moisture_percent: moisture,
        conductivity,
        salinity,
        tds,
    })
}

pub fn soil_probes() -> [SoilProbe; 2] {
    unsafe {
        [
            SoilProbe {
                device: zr_sensor_get_soil_moisture(),
                has_extended_metrics: false,
            },
            SoilProbe {
                device: zr_sensor_get_soil_moisture_three_in_one(),
                has_extended_metrics: true,
            },
        ]
    }
}

pub struct Scd41Reading {
    pub co2_ppm: u16,
    pub temperature_celsius: f32,
    pub humidity_percent: f32,
}

pub fn co2_device() -> *const device {
    unsafe { zr_sensor_get_co2() }
}

pub fn init_co2() -> Result<(), i32> {
    let result = unsafe { zr_sensor_init_co2() };
    if result == 0 {
        Ok(())
    } else {
        Err(result)
    }
}

pub fn read_scd41(device: *const device) -> Option<Scd41Reading> {
    if device.is_null() {
        return None;
    }

    unsafe {
        if sensor_sample_fetch(device as *mut _) != 0 {
            return None;
        }
    }

    let co2 = get_channel(device, sensor_channel_SENSOR_CHAN_CO2)?;
    let temperature = get_channel(device, sensor_channel_SENSOR_CHAN_AMBIENT_TEMP)?;
    let humidity = get_channel(device, sensor_channel_SENSOR_CHAN_HUMIDITY)?;

    Some(Scd41Reading {
        co2_ppm: co2 as u16,
        temperature_celsius: temperature,
        humidity_percent: humidity,
    })
}
