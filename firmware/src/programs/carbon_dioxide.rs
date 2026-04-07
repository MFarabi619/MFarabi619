use defmt::info;
use embassy_time::{Duration, Timer};
use esp_hal::i2c::master::I2c;
use scd30_interface::{asynch::Scd30, data::{AmbientPressureCompensation, DataStatus}};
use scd4x::Scd4xAsync;

use crate::config::{self, topology::{CURRENT_TOPOLOGY, SensorKind}};
use crate::state::{Co2Reading, set_co2_reading};
use crate::programs;

pub type AsyncI2cBus = I2c<'static, esp_hal::Async>;
pub type Scd30Sensor = Scd30<AsyncI2cBus>;
pub type Scd4xSensor = Scd4xAsync<AsyncI2cBus, embassy_time::Delay>;

pub enum Backend {
    Scd30(Scd30Sensor),
    Scd4x(Scd4xSensor),
}

#[derive(Clone, Copy)]
pub enum BackendKind {
    Scd30,
    Scd4x,
}

fn scd30_address() -> u8 {
    CURRENT_TOPOLOGY
        .find_sensor_of_kind(SensorKind::Scd30)
        .and_then(|sensor_configuration| sensor_configuration.i2c_address)
        .unwrap_or(0x61)
}

fn scd4x_address() -> u8 {
    CURRENT_TOPOLOGY
        .find_sensor_of_kind(SensorKind::Scd4x)
        .and_then(|sensor_configuration| sensor_configuration.i2c_address)
        .unwrap_or(0x62)
}

fn sensor_name() -> &'static str {
    CURRENT_TOPOLOGY
        .find_sensor_of_kind(SensorKind::Scd30)
        .or_else(|| CURRENT_TOPOLOGY.find_sensor_of_kind(SensorKind::Scd4x))
        .map(|sensor_configuration| sensor_configuration.name)
        .unwrap_or("carbon_dioxide_0")
}

fn model_label(backend_kind: BackendKind) -> &'static str {
    match backend_kind {
        BackendKind::Scd30 => CURRENT_TOPOLOGY
            .find_sensor_of_kind(SensorKind::Scd30)
            .map(|sensor_configuration| sensor_configuration.model)
            .unwrap_or("SCD30"),
        BackendKind::Scd4x => CURRENT_TOPOLOGY
            .find_sensor_of_kind(SensorKind::Scd4x)
            .map(|sensor_configuration| sensor_configuration.model)
            .unwrap_or("SCD4x"),
    }
}

pub async fn probe_scd30(i2c_bus: AsyncI2cBus) -> Result<Scd30Sensor, AsyncI2cBus> {
    let mut sensor = Scd30::new(i2c_bus);

    if let Err(error) = sensor.read_firmware_version().await {
        info!("SCD30 probe failed at {=u8:#x}: {:?}", scd30_address(), error);
        return Err(sensor.shutdown());
    }

    let _ = sensor.stop_continuous_measurements().await;
    Timer::after(Duration::from_millis(100)).await;

    if let Err(error) = sensor
        .trigger_continuous_measurements(Some(AmbientPressureCompensation::DefaultPressure))
        .await
    {
        info!("SCD30 start measurement failed: {:?}", error);
        return Err(sensor.shutdown());
    }

    info!("SCD30 initialized at {=u8:#x}", scd30_address());
    Ok(sensor)
}

pub async fn probe_scd4x(i2c_bus: AsyncI2cBus) -> Result<Scd4xSensor, AsyncI2cBus> {
    let mut sensor = Scd4xAsync::new(i2c_bus, embassy_time::Delay);

    if sensor.serial_number().await.is_err() {
        info!("SCD4x probe failed at {=u8:#x}", scd4x_address());
        return Err(sensor.destroy());
    }

    let _ = sensor.stop_periodic_measurement().await;
    Timer::after(Duration::from_millis(500)).await;

    if sensor.reinit().await.is_err() {
        info!("SCD4x reinit failed");
        return Err(sensor.destroy());
    }

    if sensor.start_periodic_measurement().await.is_err() {
        info!("SCD4x start measurement failed");
        return Err(sensor.destroy());
    }

    info!("SCD4x initialized at {=u8:#x}", scd4x_address());
    Ok(sensor)
}

pub async fn read_scd30(sensor: &mut Scd30Sensor) -> Result<Co2Reading, ()> {
    let mut data_ready = false;

    for _attempt in 0..programs::PROGRAMS.data_logger.poll_retries {
        match sensor.is_data_ready().await {
            Ok(status) if status == DataStatus::Ready => {
                data_ready = true;
                break;
            }
            Ok(_) => {}
            Err(error) => {
                info!("SCD30 data_ready error: {:?}", error);
                return Err(());
            }
        }
        Timer::after(Duration::from_millis(programs::PROGRAMS.data_logger.poll_interval_ms)).await;
    }

    if !data_ready {
        info!("SCD30 poll timed out");
        return Err(());
    }

    match sensor.read_measurement().await {
        Ok(measurement) => Ok(Co2Reading {
            ok: true,
            co2_ppm: measurement.co2_concentration,
            temperature: measurement.temperature,
            humidity: measurement.humidity,
            model: model_label(BackendKind::Scd30),
            name: sensor_name(),
        }),
        Err(error) => {
            info!("SCD30 read error: {:?}", error);
            Err(())
        }
    }
}

pub async fn read_scd4x(sensor: &mut Scd4xSensor) -> Result<Co2Reading, ()> {
    let mut data_ready = false;

    for _attempt in 0..config::carbon_dioxide::SCD4X_POLL_RETRIES {
        match sensor.data_ready_status().await {
            Ok(true) => {
                data_ready = true;
                break;
            }
            Ok(false) => {}
            Err(_) => {
                info!("SCD4x data_ready error");
                return Err(());
            }
        }
        Timer::after(Duration::from_millis(config::carbon_dioxide::SCD4X_POLL_INTERVAL_MS)).await;
    }

    if !data_ready {
        info!("SCD4x poll timed out");
        return Err(());
    }

    match sensor.measurement().await {
        Ok(measurement) => Ok(Co2Reading {
            ok: true,
            co2_ppm: measurement.co2 as f32,
            temperature: measurement.temperature,
            humidity: measurement.humidity,
            model: model_label(BackendKind::Scd4x),
            name: sensor_name(),
        }),
        Err(_) => {
            info!("SCD4x read error");
            Err(())
        }
    }
}

fn failed_reading(model: &'static str) -> Co2Reading {
    Co2Reading {
        model,
        name: sensor_name(),
        ..Co2Reading::default()
    }
}

#[embassy_executor::task]
pub async fn task(i2c_bus: AsyncI2cBus) {
    sensor_loop(i2c_bus).await
}

pub async fn sensor_loop(i2c_bus: AsyncI2cBus) -> ! {
    let mut current_backend: Option<Backend> = None;
    let mut bus_for_probing = Some(i2c_bus);
    let mut consecutive_failures = 0usize;

    loop {
        if current_backend.is_none() {
            let Some(bus) = bus_for_probing.take() else {
                info!("co2 probing skipped: I2C bus unavailable");
                Timer::after(Duration::from_secs(config::carbon_dioxide::PROBE_RETRY_SECS)).await;
                continue;
            };

            match probe_scd30(bus).await {
                Ok(scd30) => {
                    current_backend = Some(Backend::Scd30(scd30));
                    info!("co2 backend: {=str}", model_label(BackendKind::Scd30));
                    consecutive_failures = 0;
                    continue;
                }
                Err(bus) => {
                    match probe_scd4x(bus).await {
                        Ok(scd4x) => {
                            current_backend = Some(Backend::Scd4x(scd4x));
                            info!("co2 backend: {=str}", model_label(BackendKind::Scd4x));
                            consecutive_failures = 0;
                            continue;
                        }
                        Err(bus) => {
                            bus_for_probing = Some(bus);
                            info!(
                                "co2 probe failed; retry in {=u64}s",
                                config::carbon_dioxide::PROBE_RETRY_SECS
                            );
                            Timer::after(Duration::from_secs(
                                config::carbon_dioxide::PROBE_RETRY_SECS,
                            ))
                            .await;
                            continue;
                        }
                    }
                }
            }
        }

        let result = match current_backend.as_mut().unwrap() {
            Backend::Scd30(sensor) => read_scd30(sensor).await,
            Backend::Scd4x(sensor) => read_scd4x(sensor).await,
        };

        match result {
            Ok(reading) => {
                set_co2_reading(reading);
                consecutive_failures = 0;

                info!(
                    "{=str}: co2={=f32} temp={=f32} rh={=f32}",
                    reading.model, reading.co2_ppm, reading.temperature, reading.humidity
                );
            }
            Err(()) => {
                let model = match current_backend.as_ref().unwrap() {
                    Backend::Scd30(_) => model_label(BackendKind::Scd30),
                    Backend::Scd4x(_) => model_label(BackendKind::Scd4x),
                };

                set_co2_reading(failed_reading(model));
                consecutive_failures += 1;

                if consecutive_failures >= config::carbon_dioxide::MAX_CONSECUTIVE_FAILURES {
                    info!(
                        "co2: {=usize} consecutive failures; resetting",
                        consecutive_failures
                    );

                    let backend = current_backend.take().unwrap();
                    bus_for_probing = Some(match backend {
                        Backend::Scd30(sensor) => sensor.shutdown(),
                        Backend::Scd4x(sensor) => sensor.destroy(),
                    });
                    consecutive_failures = 0;

                    Timer::after(Duration::from_secs(1)).await;
                    continue;
                }
            }
        }

        Timer::after(Duration::from_secs(
            programs::PROGRAMS.data_logger.sampling_interval_secs,
        ))
        .await;
    }
}
