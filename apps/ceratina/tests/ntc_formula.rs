//! `describe("NTC formula (pure logic)")`
//!
//! Pure-logic unit tests for the Steinhart–Hart-style β-coefficient
//! conversion the firmware uses to derive a temperature from a measured
//! ADC voltage on a 10 kΩ NTC thermistor in a fixed-resistor divider.

#![no_std]
#![no_main]

#[path = "common/mod.rs"]
mod common;

use defmt::info;

use common::Device;

const ADC_REFERENCE_VOLTAGE_VOLTS: f32 = 3.3;
const NTC_BETA_COEFFICIENT: f32 = 3988.0;
const REFERENCE_TEMPERATURE_KELVIN: f32 = 298.15;
const NOMINAL_RESISTOR_OHMS: f32 = 10_000.0;

fn calculate_ntc_temperature_celsius_from_voltage_measured(
    measured_voltage_volts: f32,
) -> f32 {
    let voltage_fraction = measured_voltage_volts / ADC_REFERENCE_VOLTAGE_VOLTS;
    let thermistor_resistance_ratio =
        ((voltage_fraction * NOMINAL_RESISTOR_OHMS) / (1.0 - voltage_fraction))
            * (1.0 / NOMINAL_RESISTOR_OHMS);
    let inverse_temperature_kelvin = (1.0 / REFERENCE_TEMPERATURE_KELVIN)
        + (1.0 / NTC_BETA_COEFFICIENT) * libm::logf(thermistor_resistance_ratio);
    (1.0 / inverse_temperature_kelvin) - 273.15
}

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::setup]
fn setup() {
    rtt_target::rtt_init_defmt!();
}

#[cfg(test)]
#[embedded_test::tests(default_timeout = 5, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Device {
        info!("=== NTC formula (pure logic) — describe block ===");
        common::setup::boot_device()
    }

    /// `it("user reads a room-temperature reading at half-rail voltage")`
    #[test]
    async fn user_reads_room_temperature_at_half_rail_voltage(
        _device: Device,
    ) -> Result<(), &'static str> {
        let measured_voltage_volts = 1.65;
        let calculated_temperature_celsius =
            calculate_ntc_temperature_celsius_from_voltage_measured(measured_voltage_volts);

        info!(
            "1.65V on the divider → {=f32} °C",
            calculated_temperature_celsius
        );

        if calculated_temperature_celsius < 20.0 {
            return Err("device: half-rail voltage produced a temperature below room range");
        }
        if calculated_temperature_celsius > 30.0 {
            return Err("device: half-rail voltage produced a temperature above room range");
        }
        Ok(())
    }

    /// `it("user reads a cold reading at low voltage")`
    #[test]
    async fn user_reads_cold_temperature_at_low_voltage(
        _device: Device,
    ) -> Result<(), &'static str> {
        let measured_voltage_volts = 0.66;
        let calculated_temperature_celsius =
            calculate_ntc_temperature_celsius_from_voltage_measured(measured_voltage_volts);

        info!(
            "0.66V on the divider → {=f32} °C",
            calculated_temperature_celsius
        );

        if calculated_temperature_celsius >= 20.0 {
            return Err("device: low-side voltage should report a cold temperature");
        }
        Ok(())
    }

    /// `it("user reads a hot reading at high voltage")`
    #[test]
    async fn user_reads_hot_temperature_at_high_voltage(
        _device: Device,
    ) -> Result<(), &'static str> {
        let measured_voltage_volts = 2.64;
        let calculated_temperature_celsius =
            calculate_ntc_temperature_celsius_from_voltage_measured(measured_voltage_volts);

        info!(
            "2.64V on the divider → {=f32} °C",
            calculated_temperature_celsius
        );

        if calculated_temperature_celsius <= 30.0 {
            return Err("device: high-side voltage should report a hot temperature");
        }
        Ok(())
    }
}
