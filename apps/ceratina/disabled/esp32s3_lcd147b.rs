#![no_std]
#![no_main]

use embassy_time::{Duration, Timer};
use esp_hal::{
    clock::CpuClock,
    rmt::{PulseCode, Rmt},
    time::Rate,
    timer::timg::TimerGroup,
};
use esp_hal_smartled::{SmartLedsAdapterAsync, buffer_size_async};
use panic_rtt_target as _;
use smart_leds::{SmartLedsWriteAsync, hsv::Hsv, hsv::hsv2rgb};

const LED_COUNT: usize = 1;
const RMT_FREQ: Rate = Rate::from_mhz(80);
const STEP_DELAY: Duration = Duration::from_millis(24);

type LedAdapter<'a> = SmartLedsAdapterAsync<'a, { buffer_size_async(LED_COUNT) }>;

esp_bootloader_esp_idf::esp_app_desc!();

#[esp_rtos::main]
async fn main(_spawner: embassy_executor::Spawner) -> ! {
    rtt_target::rtt_init_defmt!();

    let hal_config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(hal_config);

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    esp_rtos::start(timg0.timer0);

    let rmt = Rmt::new(peripherals.RMT, RMT_FREQ).unwrap().into_async();
    let mut rmt_buffer = [PulseCode::default(); buffer_size_async(LED_COUNT)];
    let led_pin = peripherals.GPIO38;
    let mut led: LedAdapter<'_> =
        SmartLedsAdapterAsync::new(rmt.channel0, led_pin, &mut rmt_buffer);

    loop {
        for hue in 0u8..=254 {
            let color = hsv2rgb(Hsv {
                hue,
                sat: 255,
                val: 255,
            });

            led.write([color]).await.unwrap();
            Timer::after(STEP_DELAY).await;
        }
    }
}
