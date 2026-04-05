//! Modbus RTU sensor example for ESP32-S3
//!
//! Reads solar radiation, wind speed, and wind direction sensors via RS485/Modbus RTU.
//! Originally from the ceratina application, preserved here as a reference example.
//!
//! Wiring:
//!   - UART TX: GPIO45
//!   - UART RX: GPIO48
//!   - DE/RE:   GPIO47
//!   - Relay:   GPIO5 (sensor power)

#![no_std]
#![no_main]

use async_modbus::client::read_holdings;
use defmt::info;
use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use embedded_hal::digital::OutputPin;
use embedded_io_async::{ErrorType, Read, Write};
use esp_hal::{
    clock::CpuClock,
    gpio::{Level, Output, OutputConfig},
    timer::timg::TimerGroup,
    uart::{Config as UartConfig, Uart},
};
use panic_rtt_target as _;

// ─── RS485 driver ───────────────────────────────────────────────────────────

const RS485_BAUD_RATE: u32 = 9_600;
const WIND_SENSOR_DELAY_MILLIS: u64 = 100;

struct Rs485<UART, PIN> {
    uart: UART,
    direction_enable_pin: PIN,
}

impl<UART, PIN> Rs485<UART, PIN> {
    fn new(uart: UART, direction_enable_pin: PIN) -> Self {
        Self {
            uart,
            direction_enable_pin,
        }
    }
}

impl<UART, PIN> ErrorType for Rs485<UART, PIN>
where
    UART: ErrorType,
{
    type Error = UART::Error;
}

impl<UART, PIN> Read for Rs485<UART, PIN>
where
    UART: Read,
    PIN: OutputPin,
{
    async fn read(&mut self, buffer: &mut [u8]) -> Result<usize, Self::Error> {
        let _ = self.direction_enable_pin.set_low();
        self.uart.read(buffer).await
    }
}

impl<UART, PIN> Write for Rs485<UART, PIN>
where
    UART: Write,
    PIN: OutputPin,
{
    async fn write(&mut self, buffer: &[u8]) -> Result<usize, Self::Error> {
        let _ = self.direction_enable_pin.set_high();
        self.uart.write(buffer).await
    }

    async fn flush(&mut self) -> Result<(), Self::Error> {
        self.uart.flush().await?;
        let _ = self.direction_enable_pin.set_low();
        Ok(())
    }
}

// ─── Sensor constants ───────────────────────────────────────────────────────

const SOLAR_RADIATION_SLAVE_ID: u8 = 40;
const SOLAR_RADIATION_REGISTER_ADDRESS: u16 = 0;

const WIND_SPEED_SLAVE_ID: u8 = 20;
const WIND_SPEED_REGISTER_ADDRESS: u16 = 0;

const WIND_DIRECTION_SLAVE_ID: u8 = 30;
const WIND_DIRECTION_REGISTER_ADDRESS: u16 = 0;

// ─── Sensor read helpers ────────────────────────────────────────────────────

async fn read_solar_radiation_watts_per_square_meter<UART, PIN>(
    rs485: &mut Rs485<UART, PIN>,
) -> Result<u16, async_modbus::client::Error<UART::Error>>
where
    UART: Read + Write + ErrorType,
    PIN: OutputPin,
{
    let registers = read_holdings::<1, _>(
        rs485,
        SOLAR_RADIATION_SLAVE_ID,
        SOLAR_RADIATION_REGISTER_ADDRESS,
    )
    .await?;

    Ok(registers[0].get())
}

async fn read_wind_speed_kilometers_per_hour<UART, PIN>(
    rs485: &mut Rs485<UART, PIN>,
) -> Result<f32, async_modbus::client::Error<UART::Error>>
where
    UART: Read + Write + ErrorType,
    PIN: OutputPin,
{
    let registers =
        read_holdings::<1, _>(rs485, WIND_SPEED_SLAVE_ID, WIND_SPEED_REGISTER_ADDRESS).await?;
    let raw_value = registers[0].get();

    Ok((raw_value as f32 * 3.6) / 10.0)
}

struct WindDirectionReading {
    angle_degrees: f32,
    slice: u8,
}

async fn read_wind_direction<UART, PIN>(
    rs485: &mut Rs485<UART, PIN>,
) -> Result<Option<WindDirectionReading>, async_modbus::client::Error<UART::Error>>
where
    UART: Read + Write + ErrorType,
    PIN: OutputPin,
{
    let registers = read_holdings::<2, _>(
        rs485,
        WIND_DIRECTION_SLAVE_ID,
        WIND_DIRECTION_REGISTER_ADDRESS,
    )
    .await?;

    let raw_angle_times_ten = registers[0].get();
    let raw_slice = registers[1].get() as u8;

    if raw_slice > 15 {
        return Ok(None);
    }

    Ok(Some(WindDirectionReading {
        angle_degrees: raw_angle_times_ten as f32 / 10.0,
        slice: raw_slice,
    }))
}

// ─── Main ───────────────────────────────────────────────────────────────────

esp_bootloader_esp_idf::esp_app_desc!();

#[esp_rtos::main]
async fn main(_spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let hal_config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(hal_config);

    esp_alloc::heap_allocator!(size: 64 * 1024);

    let timer_group0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timer_group0.timer0);

    let _sensor_power_relay =
        Output::new(peripherals.GPIO5, Level::High, OutputConfig::default());

    let uart = Uart::new(
        peripherals.UART1,
        UartConfig::default().with_baudrate(RS485_BAUD_RATE),
    )
    .unwrap()
    .with_tx(peripherals.GPIO45)
    .with_rx(peripherals.GPIO48)
    .into_async();

    let direction_enable_pin =
        Output::new(peripherals.GPIO47, Level::Low, OutputConfig::default());
    let mut rs485 = Rs485::new(uart, direction_enable_pin);

    info!("modbus sensors example started");

    loop {
        match embassy_time::with_timeout(
            Duration::from_millis(500),
            read_solar_radiation_watts_per_square_meter(&mut rs485),
        )
        .await
        {
            Ok(Ok(watts_per_square_meter)) => {
                info!("solar radiation: {} W/m^2", watts_per_square_meter)
            }
            Ok(Err(_)) => info!("solar radiation modbus read failed"),
            Err(_) => info!("solar radiation modbus read timed out"),
        }

        match embassy_time::with_timeout(
            Duration::from_millis(500),
            read_wind_speed_kilometers_per_hour(&mut rs485),
        )
        .await
        {
            Ok(Ok(kilometers_per_hour)) => {
                info!("wind speed: {} km/h", kilometers_per_hour)
            }
            Ok(Err(_)) => info!("wind speed modbus read failed"),
            Err(_) => info!("wind speed modbus read timed out"),
        }

        Timer::after(Duration::from_millis(WIND_SENSOR_DELAY_MILLIS)).await;

        match embassy_time::with_timeout(
            Duration::from_millis(500),
            read_wind_direction(&mut rs485),
        )
        .await
        {
            Ok(Ok(Some(reading))) => {
                info!(
                    "wind direction: {} deg (slice {})",
                    reading.angle_degrees, reading.slice
                )
            }
            Ok(Ok(None)) => info!("wind direction read invalid slice"),
            Ok(Err(_)) => info!("wind direction modbus read failed"),
            Err(_) => info!("wind direction modbus read timed out"),
        }

        Timer::after(Duration::from_secs(1)).await;
    }
}
