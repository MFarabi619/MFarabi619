use defmt::info;
use embassy_time::{Duration, Timer};
use esp_hal::i2c::master::I2c;
use scd30_interface::{asynch::Scd30, data::{AmbientPressureCompensation, DataStatus}};
use scd4x::Scd4xAsync;
use statig::prelude::*;

use crate::state::{Co2Reading, set_co2_reading};
use crate::programs;

pub type AsyncI2cBus = I2c<'static, esp_hal::Async>;
pub type Scd30Sensor = Scd30<AsyncI2cBus>;
pub type Scd4xSensor = Scd4xAsync<AsyncI2cBus, embassy_time::Delay>;

#[derive(Clone, Copy)]
pub struct Config {
    pub sensor_name: &'static str,
    pub model_scd30: &'static str,
    pub model_scd4x: &'static str,
    pub scd30_i2c_address: u8,
    pub scd4x_i2c_address: u8,
    pub scd4x_poll_retries: usize,
    pub scd4x_poll_interval_ms: u64,
    pub probe_retry_secs: u64,
    pub max_consecutive_failures: usize,
}

pub const CONFIG: Config = Config {
    sensor_name: "carbon_dioxide_0",
    model_scd30: "SCD30",
    model_scd4x: "SCD4x",
    scd30_i2c_address: 0x61,
    scd4x_i2c_address: 0x62,
    scd4x_poll_retries: 20,
    scd4x_poll_interval_ms: 500,
    probe_retry_secs: 5,
    max_consecutive_failures: 5,
};

pub enum Backend {
    Scd30(Scd30Sensor),
    Scd4x(Scd4xSensor),
}

#[derive(Clone, Copy)]
pub enum BackendKind {
    Scd30,
    Scd4x,
}

#[derive(Clone, Copy)]
pub enum LifecycleEvent {
    ProbeSucceeded { kind: BackendKind },
    ProbeFailed,
    ReadSucceeded,
    ReadFailed,
    ConsecutiveFailuresExceeded,
}

mod lifecycle {
    use statig::prelude::*;

    use super::{BackendKind, LifecycleEvent};
    use defmt::info;

    #[derive(Default)]
    pub struct Lifecycle;

    #[state_machine(initial = "State::probing()")]
    impl Lifecycle {
        #[state(entry_action = "on_probing_entered")]
        fn probing(event: &LifecycleEvent) -> Outcome<State> {
            match event {
                LifecycleEvent::ProbeSucceeded { kind: BackendKind::Scd30 } => {
                    Transition(State::scd30_streaming())
                }
                LifecycleEvent::ProbeSucceeded { kind: BackendKind::Scd4x } => {
                    Transition(State::scd4x_streaming())
                }
                LifecycleEvent::ProbeFailed
                | LifecycleEvent::ReadSucceeded
                | LifecycleEvent::ReadFailed
                | LifecycleEvent::ConsecutiveFailuresExceeded => Handled,
            }
        }

        #[state(
            entry_action = "on_scd30_streaming_entered",
            exit_action = "on_streaming_exited"
        )]
        fn scd30_streaming(event: &LifecycleEvent) -> Outcome<State> {
            Self::handle_streaming_event(event)
        }

        #[state(
            entry_action = "on_scd4x_streaming_entered",
            exit_action = "on_streaming_exited"
        )]
        fn scd4x_streaming(event: &LifecycleEvent) -> Outcome<State> {
            Self::handle_streaming_event(event)
        }

        fn handle_streaming_event(event: &LifecycleEvent) -> Outcome<State> {
            match event {
                LifecycleEvent::ConsecutiveFailuresExceeded => Transition(State::probing()),
                LifecycleEvent::ProbeSucceeded { .. }
                | LifecycleEvent::ProbeFailed
                | LifecycleEvent::ReadSucceeded
                | LifecycleEvent::ReadFailed => Handled,
            }
        }

        #[action]
        fn on_probing_entered(&mut self) {
            info!("co2 lifecycle: probing");
        }

        #[action]
        fn on_scd30_streaming_entered(&mut self) {
            info!("co2 lifecycle: scd30 streaming");
        }

        #[action]
        fn on_scd4x_streaming_entered(&mut self) {
            info!("co2 lifecycle: scd4x streaming");
        }

        #[action]
        fn on_streaming_exited(&mut self) {
            info!("co2 lifecycle: exited streaming");
        }
    }
}

pub use lifecycle::Lifecycle;

pub fn backend_label(config: &Config, kind: BackendKind) -> &'static str {
    match kind {
        BackendKind::Scd30 => config.model_scd30,
        BackendKind::Scd4x => config.model_scd4x,
    }
}

pub async fn probe_scd30(config: &Config, i2c_bus: AsyncI2cBus) -> Result<Scd30Sensor, AsyncI2cBus> {
    let mut sensor = Scd30::new(i2c_bus);

    if let Err(error) = sensor.read_firmware_version().await {
        info!("SCD30 probe failed at {=u8:#x}: {:?}", config.scd30_i2c_address, error);
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

    info!("SCD30 initialized at {=u8:#x}", config.scd30_i2c_address);
    Ok(sensor)
}

pub async fn probe_scd4x(config: &Config, i2c_bus: AsyncI2cBus) -> Result<Scd4xSensor, AsyncI2cBus> {
    let mut sensor = Scd4xAsync::new(i2c_bus, embassy_time::Delay);

    if sensor.serial_number().await.is_err() {
        info!("SCD4x probe failed at {=u8:#x}", config.scd4x_i2c_address);
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

    info!("SCD4x initialized at {=u8:#x}", config.scd4x_i2c_address);
    Ok(sensor)
}

pub async fn read_scd30(config: &Config, sensor: &mut Scd30Sensor) -> Result<Co2Reading, ()> {
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
        Ok(m) => Ok(Co2Reading {
            ok: true,
            co2_ppm: m.co2_concentration,
            temperature: m.temperature,
            humidity: m.humidity,
            model: config.model_scd30,
            name: config.sensor_name,
        }),
        Err(error) => {
            info!("SCD30 read error: {:?}", error);
            Err(())
        }
    }
}

pub async fn read_scd4x(config: &Config, sensor: &mut Scd4xSensor) -> Result<Co2Reading, ()> {
    let mut data_ready = false;

    for _attempt in 0..config.scd4x_poll_retries {
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
        Timer::after(Duration::from_millis(config.scd4x_poll_interval_ms)).await;
    }

    if !data_ready {
        info!("SCD4x poll timed out");
        return Err(());
    }

    match sensor.measurement().await {
        Ok(m) => Ok(Co2Reading {
            ok: true,
            co2_ppm: m.co2 as f32,
            temperature: m.temperature,
            humidity: m.humidity,
            model: config.model_scd4x,
            name: config.sensor_name,
        }),
        Err(_) => {
            info!("SCD4x read error");
            Err(())
        }
    }
}

pub fn failed_reading(config: &Config, model: &'static str) -> Co2Reading {
    Co2Reading {
        model,
        name: config.sensor_name,
        ..Co2Reading::default()
    }
}

#[embassy_executor::task]
pub async fn task(i2c_bus: AsyncI2cBus) {
    sensor_loop(i2c_bus, &CONFIG).await
}

pub async fn sensor_loop(i2c_bus: AsyncI2cBus, config: &Config) -> ! {
    let mut lifecycle = Lifecycle::default().state_machine();
    lifecycle.init();

    let mut current_backend: Option<Backend> = None;
    let mut bus_for_probing = Some(i2c_bus);
    let mut consecutive_failures = 0usize;

    loop {
        if current_backend.is_none() {
            let Some(bus) = bus_for_probing.take() else {
                info!("co2 probing skipped: I2C bus unavailable");
                Timer::after(Duration::from_secs(config.probe_retry_secs)).await;
                continue;
            };

            match probe_scd30(config, bus).await {
                Ok(scd30) => {
                    let kind = BackendKind::Scd30;
                    current_backend = Some(Backend::Scd30(scd30));
                    lifecycle.handle(&LifecycleEvent::ProbeSucceeded { kind });
                    info!("co2 backend: {}", backend_label(config, kind));
                    consecutive_failures = 0;
                    continue;
                }
                Err(bus) => {
                    match probe_scd4x(config, bus).await {
                        Ok(scd4x) => {
                            let kind = BackendKind::Scd4x;
                            current_backend = Some(Backend::Scd4x(scd4x));
                            lifecycle.handle(&LifecycleEvent::ProbeSucceeded { kind });
                            info!("co2 backend: {}", backend_label(config, kind));
                            consecutive_failures = 0;
                            continue;
                        }
                        Err(bus) => {
                            bus_for_probing = Some(bus);
                            lifecycle.handle(&LifecycleEvent::ProbeFailed);
                            info!("co2 probe failed; retry in {}s", config.probe_retry_secs);
                            Timer::after(Duration::from_secs(config.probe_retry_secs)).await;
                            continue;
                        }
                    }
                }
            }
        }

        let result = match current_backend.as_mut().unwrap() {
            Backend::Scd30(s) => read_scd30(config, s).await,
            Backend::Scd4x(s) => read_scd4x(config, s).await,
        };

        match result {
            Ok(reading) => {
                set_co2_reading(reading);
                lifecycle.handle(&LifecycleEvent::ReadSucceeded);
                consecutive_failures = 0;

                info!(
                    "{}: co2={=f32} temp={=f32} rh={=f32}",
                    reading.model, reading.co2_ppm, reading.temperature, reading.humidity
                );
            }
            Err(()) => {
                let model = match current_backend.as_ref().unwrap() {
                    Backend::Scd30(_) => config.model_scd30,
                    Backend::Scd4x(_) => config.model_scd4x,
                };

                set_co2_reading(failed_reading(config, model));
                lifecycle.handle(&LifecycleEvent::ReadFailed);
                consecutive_failures += 1;

                if consecutive_failures >= config.max_consecutive_failures {
                    info!("co2: {} consecutive failures; resetting", consecutive_failures);
                    lifecycle.handle(&LifecycleEvent::ConsecutiveFailuresExceeded);

                    let backend = current_backend.take().unwrap();
                    bus_for_probing = Some(match backend {
                        Backend::Scd30(s) => s.shutdown(),
                        Backend::Scd4x(s) => s.destroy(),
                    });
                    consecutive_failures = 0;

                    Timer::after(Duration::from_secs(1)).await;
                    continue;
                }
            }
        }

        Timer::after(Duration::from_secs(programs::PROGRAMS.data_logger.sampling_interval_secs)).await;
    }
}
