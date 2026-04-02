#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_time::{Duration, Ticker};
use esp_hal::{
    clock::CpuClock,
    gpio::{Input, InputConfig, Pull},
    timer::timg::TimerGroup,
};
use panic_rtt_target as _;

extern crate alloc;

const BUTTON_NAMES: [&str; 3] = ["GPIO4", "GPIO42", "GPIO35"];

fn log_transition(name: &str, pressed: bool) {
    info!(
        "BTN {} = {}",
        name,
        if pressed { "PRESSED" } else { "RELEASED" }
    );
}

esp_bootloader_esp_idf::esp_app_desc!();

#[esp_rtos::main]
async fn main(_spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 73744);
    esp_alloc::heap_allocator!(size: 64 * 1024);

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timg0.timer0);

    // External pull-ups exist on board; keep internal pull disabled.
    let button_4 = Input::new(
        peripherals.GPIO4,
        InputConfig::default().with_pull(Pull::None),
    );
    let button_42 = Input::new(
        peripherals.GPIO42,
        InputConfig::default().with_pull(Pull::None),
    );
    let button_35 = Input::new(
        peripherals.GPIO35,
        InputConfig::default().with_pull(Pull::None),
    );

    let mut prev = [button_4.is_low(), button_42.is_low(), button_35.is_low()];
    let mut ticker = Ticker::every(Duration::from_millis(20));

    info!("GPIO button test started (active-low)");

    loop {
        ticker.next().await;
        let current = [button_4.is_low(), button_42.is_low(), button_35.is_low()];

        for (idx, (&now, was)) in current.iter().zip(prev.iter_mut()).enumerate() {
            if now != *was {
                log_transition(BUTTON_NAMES[idx], now);
                *was = now;
            }
        }
    }
}
