const ADC_REFERENCE_VOLTAGE_VOLTS: f32 = 3.3;
const NTC_BETA_COEFFICIENT: f32 = 3988.0;
const REFERENCE_TEMPERATURE_KELVIN: f32 = 298.15;
const NOMINAL_RESISTOR_OHMS: f32 = 10_000.0;

pub fn calculate_temperature_celsius_from_voltage(voltage_measured_volts: f32) -> f32 {
    let voltage_fraction = voltage_measured_volts / ADC_REFERENCE_VOLTAGE_VOLTS;

    let thermistor_resistance_ratio = ((voltage_fraction * NOMINAL_RESISTOR_OHMS)
        / (1.0 - voltage_fraction))
        * (1.0 / NOMINAL_RESISTOR_OHMS);

    let inverse_temperature_kelvin = (1.0 / REFERENCE_TEMPERATURE_KELVIN)
        + (1.0 / NTC_BETA_COEFFICIENT) * libm::logf(thermistor_resistance_ratio);

    (1.0 / inverse_temperature_kelvin) - 273.15
}
