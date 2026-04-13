#![no_std]
#![no_main]

use core::time::Duration;

use defmt::info;
use embassy_executor::Spawner;
use esp_hal::{
    delay::Delay,
    interrupt::software::SoftwareInterruptControl,
    rtc_cntl::{Rtc, SocResetReason, reset_reason, sleep::TimerWakeupSource, wakeup_cause},
    system::Cpu,
    timer::timg::TimerGroup,
};
use panic_rtt_target as _;

const DEEP_SLEEP_DURATION_SECONDS: u64 = 5;

esp_bootloader_esp_idf::esp_app_desc!();

#[esp_rtos::main]
async fn main(_spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let peripherals = esp_hal::init(esp_hal::Config::default());

    let timer_group0 = TimerGroup::new(peripherals.TIMG0);
    let sw_ints = SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
    esp_rtos::start(timer_group0.timer0, sw_ints.software_interrupt0);

    let delay = Delay::new();
    let mut rtc = Rtc::new(peripherals.LPWR);

    let reset_reason = reset_reason(Cpu::ProCpu).unwrap_or(SocResetReason::ChipPowerOn);
    let wakeup_cause = wakeup_cause();

    info!(
        "deep_sleep example start (reset_reason={}, wakeup_cause={})",
        reset_reason as u8,
        wakeup_cause as u8
    );

    if reset_reason == SocResetReason::CoreDeepSleep {
        info!("woke from deep sleep successfully");
    }

    info!("entering deep sleep for {} seconds", DEEP_SLEEP_DURATION_SECONDS);

    let timer_wakeup_source = TimerWakeupSource::new(Duration::from_secs(DEEP_SLEEP_DURATION_SECONDS));

    delay.delay_millis(100);
    rtc.sleep_deep(&[&timer_wakeup_source]);
}
