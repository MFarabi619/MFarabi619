#![no_std]
#![no_main]

use defmt::{info, warn};
use embassy_executor::Spawner;
use embassy_time::{Duration, Ticker, Timer};
use esp_hal::{
    clock::CpuClock,
    gpio::{Level, Output, OutputConfig},
    i2c::master::{Config as I2cConfig, I2c},
    interrupt::software::SoftwareInterruptControl,
    time::Rate,
    timer::timg::TimerGroup,
};
use panic_rtt_target as _;

extern crate alloc;

const I2C0_SDA_GPIO_PIN: u8 = 8;
const I2C0_SCL_GPIO_PIN: u8 = 9;
const I2C_BUS_FREQUENCY_KHZ: u32 = 100;

const SENSOR_CANDIDATE_ADDRESSES: [u8; 4] = [0x44, 0x45, 0x46, 0x47];

const OPTIONAL_MUX_ADDRESS: Option<u8> = None;
const OPTIONAL_MUX_CHANNEL: Option<u8> = None;

const COMMAND_ONE_SHOT_CLOCK_STRETCHING_DISABLED: [u8; 2] = [0x24, 0x00];
const COMMAND_SOFT_RESET: [u8; 2] = [0x30, 0xA2];
const COMMAND_READ_MANUFACTURER_ID: [u8; 2] = [0x37, 0x81];

const EXPECTED_MANUFACTURER_ID_MSB: u8 = 0x59;
const EXPECTED_MANUFACTURER_ID_LSB: u8 = 0x59;

esp_bootloader_esp_idf::esp_app_desc!();

#[esp_rtos::main]
async fn main(_spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let hal_configuration = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(hal_configuration);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 73744);
    esp_alloc::heap_allocator!(size: 64 * 1024);

    let timer_group0 = TimerGroup::new(peripherals.TIMG0);
    let sw_ints = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
    esp_rtos::start(timer_group0.timer0, sw_ints.software_interrupt0);

    let _sensor_power_relay =
        Output::new(peripherals.GPIO5, Level::High, OutputConfig::default());
    Timer::after(Duration::from_millis(1_000)).await;

    let mut i2c_bus = I2c::new(
        peripherals.I2C0,
        I2cConfig::default().with_frequency(Rate::from_khz(I2C_BUS_FREQUENCY_KHZ)),
    )
    .unwrap()
    .with_sda(peripherals.GPIO8)
    .with_scl(peripherals.GPIO9)
    .into_async();

    info!(
        "cht832x bring-up on I2C0 (SDA=GPIO{}, SCL=GPIO{}, {}kHz)",
        I2C0_SDA_GPIO_PIN,
        I2C0_SCL_GPIO_PIN,
        I2C_BUS_FREQUENCY_KHZ
    );

    if let (Some(multiplexer_address), Some(multiplexer_channel)) =
        (OPTIONAL_MUX_ADDRESS, OPTIONAL_MUX_CHANNEL)
    {
        let multiplexer_channel_mask: u8 = 1_u8 << multiplexer_channel;
        if i2c_bus
            .write_async(multiplexer_address, &[multiplexer_channel_mask])
            .await
            .is_ok()
        {
            info!(
                "selected mux channel {} on address {}",
                multiplexer_channel,
                multiplexer_address
            );
        } else {
            warn!(
                "failed to select mux channel {} on address {}",
                multiplexer_channel,
                multiplexer_address
            );
        }
    }

    let mut discovered_sensor_address: Option<u8> = None;
    for sensor_candidate_address in SENSOR_CANDIDATE_ADDRESSES {
        if i2c_bus.write_async(sensor_candidate_address, &[]).await.is_ok() {
            discovered_sensor_address = Some(sensor_candidate_address);
            break;
        }
    }

    let sensor_address = if let Some(sensor_address) = discovered_sensor_address {
        sensor_address
    } else {
        warn!("no CHT832X found at addresses 0x44..0x47");
        loop {
            Timer::after(Duration::from_secs(1)).await;
        }
    };

    info!("using CHT832X at address {}", sensor_address);

    if i2c_bus
        .write_async(sensor_address, &COMMAND_SOFT_RESET)
        .await
        .is_ok()
    {
        info!("soft reset command sent");
    } else {
        warn!("soft reset command failed");
    }

    Timer::after(Duration::from_millis(5)).await;

    let mut manufacturer_id_response = [0_u8; 3];
    if i2c_bus
        .write_read_async(
            sensor_address,
            &COMMAND_READ_MANUFACTURER_ID,
            &mut manufacturer_id_response,
        )
        .await
        .is_ok()
    {
        let expected_manufacturer_crc =
            calculate_crc8(&[EXPECTED_MANUFACTURER_ID_MSB, EXPECTED_MANUFACTURER_ID_LSB]);
        let manufacturer_id_matches = manufacturer_id_response[0] == EXPECTED_MANUFACTURER_ID_MSB
            && manufacturer_id_response[1] == EXPECTED_MANUFACTURER_ID_LSB;
        let manufacturer_crc_matches = manufacturer_id_response[2] == expected_manufacturer_crc;

        if manufacturer_id_matches && manufacturer_crc_matches {
            info!("manufacturer id verified: 0x5959");
        } else {
            warn!(
                "manufacturer id unexpected: data=[{},{}] crc={}",
                manufacturer_id_response[0],
                manufacturer_id_response[1],
                manufacturer_id_response[2]
            );
        }
    } else {
        warn!("manufacturer id read failed");
    }

    let mut measurement_interval = Ticker::every(Duration::from_secs(1));

    loop {
        measurement_interval.next().await;

        match read_measurement_once(&mut i2c_bus, sensor_address).await {
            Ok((temperature_celsius, relative_humidity_percent)) => info!(
                "temperature={}C humidity={}%RH",
                temperature_celsius,
                relative_humidity_percent
            ),
            Err(error_message) => warn!("measurement failed: {}", error_message),
        }
    }
}

async fn read_measurement_once(
    i2c_bus: &mut I2c<'_, esp_hal::Async>,
    sensor_address: u8,
) -> Result<(f32, f32), &'static str> {
    i2c_bus
        .write_async(sensor_address, &COMMAND_ONE_SHOT_CLOCK_STRETCHING_DISABLED)
        .await
        .map_err(|_| "failed to send one-shot command")?;

    Timer::after(Duration::from_millis(60)).await;

    let mut measurement_buffer = [0_u8; 6];
    i2c_bus
        .read_async(sensor_address, &mut measurement_buffer)
        .await
        .map_err(|_| "failed to read one-shot measurement")?;

    let temperature_bytes = [measurement_buffer[0], measurement_buffer[1]];
    let humidity_bytes = [measurement_buffer[3], measurement_buffer[4]];
    let received_temperature_crc = measurement_buffer[2];
    let received_humidity_crc = measurement_buffer[5];

    let expected_temperature_crc = calculate_crc8(&temperature_bytes);
    let expected_humidity_crc = calculate_crc8(&humidity_bytes);

    if received_temperature_crc != expected_temperature_crc {
        return Err("temperature crc mismatch");
    }

    if received_humidity_crc != expected_humidity_crc {
        return Err("humidity crc mismatch");
    }

    let temperature_raw_value = u16::from_be_bytes(temperature_bytes);
    let humidity_raw_value = u16::from_be_bytes(humidity_bytes);

    Ok((
        convert_temperature_celsius(temperature_raw_value),
        convert_relative_humidity_percent(humidity_raw_value),
    ))
}

fn convert_temperature_celsius(temperature_raw_value: u16) -> f32 {
    -45.0 + 175.0 * (temperature_raw_value as f32 / 65535.0)
}

fn convert_relative_humidity_percent(humidity_raw_value: u16) -> f32 {
    100.0 * (humidity_raw_value as f32 / 65535.0)
}

fn calculate_crc8(data_bytes: &[u8]) -> u8 {
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
