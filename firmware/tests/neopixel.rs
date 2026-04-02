#![no_std]
#![no_main]

use defmt::info;
use embassy_time::Timer;
use esp_hal::{clock::CpuClock, gpio::AnyPin, rmt::Rmt, time::Rate, timer::timg::TimerGroup};
use esp_hal_smartled::{SmartLedsAdapterAsync, buffer_size_async};
use smart_leds::{RGB8, SmartLedsWriteAsync, hsv::hsv2rgb};

const NEOPIXEL_BRIGHTNESS: u8 = 150;

struct Context {
    rmt: esp_hal::peripherals::RMT<'static>,
    neopixel_pin: AnyPin<'static>,
}

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::tests(executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> Context {
        let hal_config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
        let peripherals = esp_hal::init(hal_config);

        let timg0 = TimerGroup::new(peripherals.TIMG0);
        esp_rtos::start(timg0.timer0);

        rtt_target::rtt_init_defmt!();

        Context {
            rmt: peripherals.RMT,
            neopixel_pin: peripherals.GPIO38.into(),
        }
    }

    #[test]
    async fn neopixel_red(mut ctx: Context) {
        let rmt = Rmt::new(ctx.rmt.reborrow(), Rate::from_mhz(80))
            .unwrap()
            .into_async();

        let mut rmt_buffer = [esp_hal::rmt::PulseCode::default(); buffer_size_async(1)];
        let mut led = SmartLedsAdapterAsync::new(rmt.channel0, ctx.neopixel_pin, &mut rmt_buffer);

        info!("LED red");
        led.write([RGB8::new(255, 0, 0)]).await.unwrap();
        Timer::after(embassy_time::Duration::from_secs(1)).await;
        led.write([RGB8::default()]).await.unwrap();
    }

    #[test]
    async fn neopixel_rainbow(mut ctx: Context) {
        let rmt = Rmt::new(ctx.rmt.reborrow(), Rate::from_mhz(80))
            .unwrap()
            .into_async();

        let mut rmt_buffer = [esp_hal::rmt::PulseCode::default(); buffer_size_async(1)];
        let mut led = SmartLedsAdapterAsync::new(rmt.channel0, ctx.neopixel_pin, &mut rmt_buffer);

        info!("rainbow cycle");
        for hue in (0..=255).step_by(64) {
            let rgb = hsv2rgb(smart_leds::hsv::Hsv {
                hue,
                sat: 255,
                val: 255,
            });
            led.write([rgb]).await.unwrap();
            Timer::after(embassy_time::Duration::from_millis(200)).await;
        }
        led.write([RGB8::default()]).await.unwrap();
    }

    #[test]
    async fn neopixel_colors(mut ctx: Context) {
        let rmt = Rmt::new(ctx.rmt.reborrow(), Rate::from_mhz(80))
            .unwrap()
            .into_async();

        let mut rmt_buffer = [esp_hal::rmt::PulseCode::default(); buffer_size_async(1)];
        let mut led = SmartLedsAdapterAsync::new(rmt.channel0, ctx.neopixel_pin, &mut rmt_buffer);

        let colors: [(RGB8, &str); 6] = [
            (RGB8::new(255, 0, 0), "RED"),
            (RGB8::new(0, 255, 0), "GREEN"),
            (RGB8::new(0, 0, 255), "BLUE"),
            (RGB8::new(255, 255, 0), "YELLOW"),
            (RGB8::new(255, 0, 255), "MAGENTA"),
            (RGB8::new(0, 255, 255), "CYAN"),
        ];

        for (color, name) in colors {
            info!("color: {}", name);
            led.write([color]).await.unwrap();
            Timer::after(embassy_time::Duration::from_millis(300)).await;
        }
        led.write([RGB8::default()]).await.unwrap();
    }
}
