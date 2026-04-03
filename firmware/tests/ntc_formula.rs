#![no_std]
#![no_main]

use defmt::info;
use esp_hal::timer::timg::TimerGroup;

const ADC_REFERENCE_VOLTAGE_VOLTS: f32 = 3.3;
const NTC_BETA_COEFFICIENT: f32 = 3988.0;
const REFERENCE_TEMPERATURE_KELVIN: f32 = 298.15;
const NOMINAL_RESISTOR_OHMS: f32 = 10_000.0;

fn calculate_ntc_temperature_celsius_from_voltage_measured(voltage_measured_volts: f32) -> f32 {
    let voltage_fraction = voltage_measured_volts / ADC_REFERENCE_VOLTAGE_VOLTS;

    let thermistor_resistance_ratio =
        ((voltage_fraction * NOMINAL_RESISTOR_OHMS) / (1.0 - voltage_fraction))
            * (1.0 / NOMINAL_RESISTOR_OHMS);

    let inverse_temperature_kelvin = (1.0 / REFERENCE_TEMPERATURE_KELVIN)
        + (1.0 / NTC_BETA_COEFFICIENT) * libm::logf(thermistor_resistance_ratio);

    (1.0 / inverse_temperature_kelvin) - 273.15
}

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::tests(executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() {
        let peripherals = esp_hal::init(esp_hal::Config::default());

        let timer_group0 = TimerGroup::new(peripherals.TIMG0);
        esp_rtos::start(timer_group0.timer0);

        rtt_target::rtt_init_defmt!();
        info!("NTC formula test initialized");
    }

    #[test]
    async fn ntc_formula_returns_reasonable_temperature_for_mid_scale_voltage() {
        let measured_voltage_volts = 1.65;

        let calculated_temperature_celsius =
            calculate_ntc_temperature_celsius_from_voltage_measured(measured_voltage_volts);

        info!(
            "measured_voltage={}V calculated_temperature={}C",
            measured_voltage_volts,
            calculated_temperature_celsius
        );

        defmt::assert!(calculated_temperature_celsius > 20.0);
        defmt::assert!(calculated_temperature_celsius < 30.0);
    }
}
