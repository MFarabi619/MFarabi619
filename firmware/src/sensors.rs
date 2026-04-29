use zephyr::raw::*;

const SENSOR_CHAN_CERATINA_WIND_SPEED: u32 = sensor_channel_SENSOR_CHAN_PRIV_START;
const SENSOR_CHAN_CERATINA_WIND_DIRECTION_DEGREES: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 1;
const SENSOR_CHAN_CERATINA_WIND_DIRECTION_SLICE: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 2;
const SENSOR_CHAN_CERATINA_RAINFALL: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 3;
const SENSOR_CHAN_CERATINA_SOIL_MOISTURE: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 4;
const SENSOR_CHAN_CERATINA_SOIL_CONDUCTIVITY: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 5;
const SENSOR_CHAN_CERATINA_SOIL_SALINITY: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 6;
const SENSOR_CHAN_CERATINA_SOIL_TDS: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 7;
const SENSOR_CHAN_CERATINA_SOIL_PH: u32 = sensor_channel_SENSOR_CHAN_PRIV_START + 8;

const SENSOR_ATTR_CERATINA_CLEAR: u32 = sensor_attribute_SENSOR_ATTR_PRIV_START;
const SENSOR_ATTR_CERATINA_SCAN: u32 = sensor_attribute_SENSOR_ATTR_PRIV_START + 1;
const SENSOR_ATTR_CERATINA_SLAVE_ID: u32 = sensor_attribute_SENSOR_ATTR_PRIV_START + 2;

unsafe extern "C" {
    fn zr_sensor_get_wind_speed() -> *const device;
    fn zr_sensor_get_wind_direction() -> *const device;
    fn zr_sensor_get_rainfall() -> *const device;
    fn zr_sensor_get_soil_tier1() -> *const device;
    fn zr_sensor_get_soil_tier2() -> *const device;
    fn zr_sensor_get_soil_tier3() -> *const device;
}

fn sensor_value_to_f32(value: &sensor_value) -> f32 {
    value.val1 as f32 + value.val2 as f32 / 1_000_000.0
}

fn fetch_channel(dev: *const device, channel: u32) -> Option<f32> {
    if dev.is_null() {
        return None;
    }

    unsafe {
        if sensor_sample_fetch(dev as *mut _) != 0 {
            return None;
        }

        let mut value: sensor_value = core::mem::zeroed();
        if sensor_channel_get(dev as *mut _, channel, &mut value) != 0 {
            return None;
        }

        Some(sensor_value_to_f32(&value))
    }
}

fn get_channel(dev: *const device, channel: u32) -> Option<f32> {
    if dev.is_null() {
        return None;
    }

    unsafe {
        let mut value: sensor_value = core::mem::zeroed();
        if sensor_channel_get(dev as *mut _, channel, &mut value) != 0 {
            return None;
        }

        Some(sensor_value_to_f32(&value))
    }
}

fn set_attribute(dev: *const device, channel: u32, attribute: u32, val1: i32) -> bool {
    if dev.is_null() {
        return false;
    }

    unsafe {
        let value = sensor_value {
            val1,
            val2: 0,
        };
        sensor_attr_set(
            dev as *mut _,
            channel,
            attribute,
            &value,
        ) == 0
    }
}

pub struct WindSpeedReading {
    pub wind_speed_kilometers_per_hour: f32,
}

pub struct WindDirectionReading {
    pub wind_direction_degrees: f32,
    pub wind_direction_angle_slice: u8,
}

pub struct RainfallReading {
    pub rainfall_millimeters: f32,
}

pub struct SoilReading {
    pub slave_id: u8,
    pub temperature_celsius: f32,
    pub moisture_percent: f32,
    pub conductivity: Option<u16>,
    pub salinity: Option<u16>,
    pub tds: Option<u16>,
    pub ph: Option<f32>,
}

pub fn read_wind_speed() -> Option<WindSpeedReading> {
    let dev = unsafe { zr_sensor_get_wind_speed() };
    let speed = fetch_channel(dev, SENSOR_CHAN_CERATINA_WIND_SPEED)?;

    Some(WindSpeedReading {
        wind_speed_kilometers_per_hour: speed,
    })
}

pub fn read_wind_direction() -> Option<WindDirectionReading> {
    let dev = unsafe { zr_sensor_get_wind_direction() };

    if dev.is_null() {
        return None;
    }

    unsafe {
        if sensor_sample_fetch(dev as *mut _) != 0 {
            return None;
        }
    }

    let degrees = get_channel(dev, SENSOR_CHAN_CERATINA_WIND_DIRECTION_DEGREES)?;
    let slice = get_channel(dev, SENSOR_CHAN_CERATINA_WIND_DIRECTION_SLICE)?;

    Some(WindDirectionReading {
        wind_direction_degrees: degrees,
        wind_direction_angle_slice: slice as u8,
    })
}

pub fn read_rainfall() -> Option<RainfallReading> {
    let dev = unsafe { zr_sensor_get_rainfall() };
    let rainfall = fetch_channel(dev, SENSOR_CHAN_CERATINA_RAINFALL)?;

    Some(RainfallReading {
        rainfall_millimeters: rainfall,
    })
}

pub fn clear_rainfall() -> bool {
    let dev = unsafe { zr_sensor_get_rainfall() };
    set_attribute(dev, SENSOR_CHAN_CERATINA_RAINFALL, SENSOR_ATTR_CERATINA_CLEAR, 0)
}

pub fn read_soil(dev: *const device, probe_index: u8) -> Option<SoilReading> {
    set_attribute(dev, 0, SENSOR_ATTR_CERATINA_SLAVE_ID, probe_index as i32);

    unsafe {
        if sensor_sample_fetch(dev as *mut _) != 0 {
            return None;
        }
    }

    let moisture = get_channel(dev, SENSOR_CHAN_CERATINA_SOIL_MOISTURE)?;
    let temperature = get_channel(dev, sensor_channel_SENSOR_CHAN_AMBIENT_TEMP)?;

    let conductivity = get_channel(dev, SENSOR_CHAN_CERATINA_SOIL_CONDUCTIVITY)
        .map(|value| value as u16);
    let salinity = get_channel(dev, SENSOR_CHAN_CERATINA_SOIL_SALINITY)
        .map(|value| value as u16);
    let tds = get_channel(dev, SENSOR_CHAN_CERATINA_SOIL_TDS)
        .map(|value| value as u16);
    let ph = get_channel(dev, SENSOR_CHAN_CERATINA_SOIL_PH);

    let mut slave_value: sensor_value = unsafe { core::mem::zeroed() };
    let slave_id = unsafe {
        if sensor_attr_get(
            dev as *mut _,
            0,
            SENSOR_ATTR_CERATINA_SLAVE_ID,
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
        ph,
    })
}

pub fn soil_devices() -> [*const device; 3] {
    unsafe {
        [
            zr_sensor_get_soil_tier1(),
            zr_sensor_get_soil_tier2(),
            zr_sensor_get_soil_tier3(),
        ]
    }
}

pub fn soil_probe_count(dev: *const device) -> u8 {
    if dev.is_null() {
        return 0;
    }

    unsafe {
        let mut value: sensor_value = core::mem::zeroed();
        if sensor_attr_get(
            dev as *mut _,
            0,
            SENSOR_ATTR_CERATINA_SCAN,
            &mut value,
        ) == 0
        {
            value.val1 as u8
        } else {
            0
        }
    }
}
