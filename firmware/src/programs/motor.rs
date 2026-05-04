use core::sync::atomic::{AtomicBool, AtomicU32, AtomicU8, Ordering};
use log_04::info;
use zephyr::raw::*;

const GPIO_PIN_R_EN: u8 = 5;
const GPIO_PIN_L_EN: u8 = 6;
const PWM_CHANNEL_LPWM: u32 = 0;
const PWM_CHANNEL_RPWM: u32 = 1;
const DEFAULT_FREQUENCY_HZ: u32 = 20_000;
const MIN_FREQUENCY_HZ: u32 = 100;
const MAX_FREQUENCY_HZ: u32 = 25_000;

static SPEED_MAGNITUDE: AtomicU8 = AtomicU8::new(0);
static IS_FORWARD: AtomicBool = AtomicBool::new(true);
static FREQUENCY_HZ: AtomicU32 = AtomicU32::new(DEFAULT_FREQUENCY_HZ);
static IS_ACTIVE: AtomicBool = AtomicBool::new(false);
static IS_BRAKING: AtomicBool = AtomicBool::new(false);

pub fn init() {
    unsafe {
        let gpio = zr_device_get_gpio0();
        let pwm = zr_device_get_ledc0();
        if gpio.is_null() || pwm.is_null() {
            info!("Motor init skipped: gpio0 or ledc0 device unavailable");
            return;
        }
        gpio_pin_configure(gpio, GPIO_PIN_R_EN, ZR_GPIO_OUTPUT | ZR_GPIO_OUTPUT_INIT_LOW);
        gpio_pin_configure(gpio, GPIO_PIN_L_EN, ZR_GPIO_OUTPUT | ZR_GPIO_OUTPUT_INIT_LOW);
        let period_ns = period_ns_from_hz(DEFAULT_FREQUENCY_HZ);
        pwm_set(pwm, PWM_CHANNEL_LPWM, period_ns, 0, 0);
        pwm_set(pwm, PWM_CHANNEL_RPWM, period_ns, 0, 0);
    }
    info!("Motor initialised; disabled until commanded");
}

pub fn set_active(is_active_request: bool) {
    let was_active = IS_ACTIVE.swap(is_active_request, Ordering::Relaxed);
    if was_active == is_active_request {
        return;
    }
    if is_active_request {
        write_enables(true);
        let pending_magnitude = SPEED_MAGNITUDE.load(Ordering::Relaxed);
        if pending_magnitude != 0 && !IS_BRAKING.load(Ordering::Relaxed) {
            apply_speed(pending_magnitude);
        }
    } else {
        SPEED_MAGNITUDE.store(0, Ordering::Relaxed);
        IS_BRAKING.store(false, Ordering::Relaxed);
        write_outputs(0, 0);
        write_enables(false);
    }
}

pub fn set_speed(magnitude: u8) {
    let clamped = magnitude.min(100);
    SPEED_MAGNITUDE.store(clamped, Ordering::Relaxed);
    IS_BRAKING.store(false, Ordering::Relaxed);
    if !IS_ACTIVE.load(Ordering::Relaxed) {
        return;
    }
    apply_speed(clamped);
}

pub fn set_direction(is_forward: bool) {
    IS_FORWARD.store(is_forward, Ordering::Relaxed);
    if !IS_ACTIVE.load(Ordering::Relaxed) || IS_BRAKING.load(Ordering::Relaxed) {
        return;
    }
    apply_speed(SPEED_MAGNITUDE.load(Ordering::Relaxed));
}

pub fn set_frequency(hz: u32) {
    let clamped = hz.clamp(MIN_FREQUENCY_HZ, MAX_FREQUENCY_HZ);
    FREQUENCY_HZ.store(clamped, Ordering::Relaxed);
    if IS_ACTIVE.load(Ordering::Relaxed) && !IS_BRAKING.load(Ordering::Relaxed) {
        apply_speed(SPEED_MAGNITUDE.load(Ordering::Relaxed));
    }
}

pub fn brake() {
    if !IS_ACTIVE.load(Ordering::Relaxed) {
        return;
    }
    SPEED_MAGNITUDE.store(0, Ordering::Relaxed);
    IS_BRAKING.store(true, Ordering::Relaxed);
    write_outputs(0, 0);
    write_enables(true);
}

pub fn coast() {
    SPEED_MAGNITUDE.store(0, Ordering::Relaxed);
    IS_BRAKING.store(false, Ordering::Relaxed);
    IS_ACTIVE.store(false, Ordering::Relaxed);
    write_outputs(0, 0);
    write_enables(false);
}

pub fn current_speed() -> u8 {
    SPEED_MAGNITUDE.load(Ordering::Relaxed)
}

pub fn current_direction() -> bool {
    IS_FORWARD.load(Ordering::Relaxed)
}

pub fn current_frequency() -> u32 {
    FREQUENCY_HZ.load(Ordering::Relaxed)
}

pub fn is_active() -> bool {
    IS_ACTIVE.load(Ordering::Relaxed)
}

pub fn is_braking() -> bool {
    IS_BRAKING.load(Ordering::Relaxed)
}

fn period_ns_from_hz(hz: u32) -> u32 {
    1_000_000_000u32 / hz
}

fn apply_speed(magnitude: u8) {
    let period_ns = period_ns_from_hz(FREQUENCY_HZ.load(Ordering::Relaxed));
    let pulse_ns = period_ns.saturating_mul(magnitude as u32) / 100;
    let (lpwm_ns, rpwm_ns) = if pulse_ns == 0 {
        (0, 0)
    } else if IS_FORWARD.load(Ordering::Relaxed) {
        (0, pulse_ns)
    } else {
        (pulse_ns, 0)
    };
    write_outputs_ns(period_ns, lpwm_ns, rpwm_ns);
}

fn write_outputs(lpwm_ns: u32, rpwm_ns: u32) {
    let period_ns = period_ns_from_hz(FREQUENCY_HZ.load(Ordering::Relaxed));
    write_outputs_ns(period_ns, lpwm_ns, rpwm_ns);
}

fn write_outputs_ns(period_ns: u32, lpwm_ns: u32, rpwm_ns: u32) {
    unsafe {
        let pwm = zr_device_get_ledc0();
        if pwm.is_null() {
            return;
        }
        pwm_set(pwm, PWM_CHANNEL_LPWM, period_ns, lpwm_ns, 0);
        pwm_set(pwm, PWM_CHANNEL_RPWM, period_ns, rpwm_ns, 0);
    }
}

fn write_enables(should_be_high: bool) {
    unsafe {
        let gpio = zr_device_get_gpio0();
        if gpio.is_null() {
            return;
        }
        let value = if should_be_high { 1 } else { 0 };
        gpio_pin_set_raw(gpio, GPIO_PIN_R_EN, value);
        gpio_pin_set_raw(gpio, GPIO_PIN_L_EN, value);
    }
}
