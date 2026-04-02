// Thanks to: https://github.com/esp-rs/esp-hal-community/blob/main/esp-hal-smartled/examples/hello_rgb_async.rs
#![no_std]
#![no_main]
#![deny(
    clippy::mem_forget,
    reason = "mem::forget is generally not safe to do with esp_hal types, especially those \
    holding buffers for the duration of a data transfer."
)]
#![deny(clippy::large_stack_frames)]

use defmt::info;
use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use esp_hal::{clock::CpuClock, rmt::Rmt, time::Rate, timer::timg::TimerGroup};
use esp_hal_smartled::{SmartLedsAdapterAsync, buffer_size_async};
use panic_rtt_target as _;
use smart_leds::{
    RGB8, SmartLedsWriteAsync, brightness, gamma,
    hsv::{Hsv, hsv2rgb},
};

extern crate alloc;

esp_bootloader_esp_idf::esp_app_desc!();

#[allow(
    clippy::large_stack_frames,
    reason = "it's not unusual to allocate larger buffers etc. in main"
)]
#[esp_rtos::main]
async fn main(_spawner: Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 73744);
    esp_alloc::heap_allocator!(size: 64 * 1024);

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timg0.timer0);

    let rmt: Rmt<'_, esp_hal::Async> = Rmt::new(peripherals.RMT, Rate::from_mhz(80))
        .unwrap()
        .into_async();
    let mut rmt_buffer = [esp_hal::rmt::PulseCode::default(); buffer_size_async(1)];
    let mut led = SmartLedsAdapterAsync::new(rmt.channel0, peripherals.GPIO38, &mut rmt_buffer);

    let mut color = Hsv {
        hue: 0,
        sat: 255,
        val: 255,
    };
    let mut data: RGB8;
    let level = 150;

    loop {
        info!("neopixel rainbow");
        for hue in 0..=255 {
            color.hue = hue;
            data = hsv2rgb(color);
            led.write(brightness(gamma([data].into_iter()), level))
                .await
                .unwrap();
            Timer::after(Duration::from_millis(10)).await;
        }
    }
}
