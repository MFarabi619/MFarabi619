#![no_std]
#![no_main]

use defmt::info;
use embassy_time::{Duration, Timer};
use esp_hal::{
    clock::CpuClock,
    gpio::AnyPin,
    peripherals::RMT,
    rmt::{PulseCode, Rmt},
    time::Rate,
    timer::timg::TimerGroup,
};
use esp_hal_smartled::{buffer_size_async, SmartLedsAdapterAsync};
use smart_leds::{RGB8, SmartLedsWriteAsync, hsv::hsv2rgb};

const NEOPIXEL_BUFFER_SIZE: usize = buffer_size_async(1);
const NEOPIXEL_CHANNEL_FREQUENCY: Rate = Rate::from_mhz(80);
const RED_DISPLAY_DURATION: Duration = Duration::from_secs(1);
const RAINBOW_STEP_DURATION_MIN_MILLIS: u64 = 4;
const RAINBOW_STEP_DURATION_MAX_MILLIS: u64 = 28;
const RAINBOW_HUE_COUNT: u16 = 255;
const FINAL_HUE_DISPLAY_DURATION: Duration = Duration::from_secs(3);
const COLOR_SEQUENCE_STEP_DURATION: Duration = Duration::from_millis(300);
const FINAL_HUE: u8 = 170;
const COLOR_SEQUENCE: [(RGB8, &str); 6] = [
    (RGB8::new(255, 0, 0), "RED"),
    (RGB8::new(0, 255, 0), "GREEN"),
    (RGB8::new(0, 0, 255), "BLUE"),
    (RGB8::new(255, 255, 0), "YELLOW"),
    (RGB8::new(255, 0, 255), "MAGENTA"),
    (RGB8::new(0, 255, 255), "CYAN"),
];

struct Context {
    rmt: RMT<'static>,
    neopixel_pin: AnyPin<'static>,
}

type NeopixelAdapter<'channel> = SmartLedsAdapterAsync<'channel, NEOPIXEL_BUFFER_SIZE>;

fn create_led_adapter<'context, 'buffer>(
    context: &'context mut Context,
    rmt_buffer: &'buffer mut [PulseCode; NEOPIXEL_BUFFER_SIZE],
) -> NeopixelAdapter<'context>
where
    'buffer: 'context,
{
    let rmt = Rmt::new(context.rmt.reborrow(), NEOPIXEL_CHANNEL_FREQUENCY)
        .unwrap()
        .into_async();

    SmartLedsAdapterAsync::new(rmt.channel0, context.neopixel_pin.reborrow(), rmt_buffer)
}

async fn write_color(led: &mut NeopixelAdapter<'_>, color: RGB8) {
    led.write([color]).await.unwrap();
}

async fn clear_led(led: &mut NeopixelAdapter<'_>) {
    write_color(led, RGB8::default()).await;
}

async fn pause(duration: Duration) {
    Timer::after(duration).await;
}

fn rgb_from_hue(hue: u8) -> RGB8 {
    hsv2rgb(smart_leds::hsv::Hsv {
        hue,
        sat: 255,
        val: 255,
    })
}

fn rainbow_step_duration(hue: u8) -> Duration {
    let hue_position = hue as u16;
    let last_hue_position = RAINBOW_HUE_COUNT - 1;
    let distance_from_center = hue_position.abs_diff(last_hue_position / 2);
    let max_distance_from_center = last_hue_position / 2;
    let duration_range = RAINBOW_STEP_DURATION_MAX_MILLIS - RAINBOW_STEP_DURATION_MIN_MILLIS;

    let scaled_slowdown = duration_range * u64::from(distance_from_center)
        / u64::from(max_distance_from_center.max(1));

    Duration::from_millis(RAINBOW_STEP_DURATION_MIN_MILLIS + scaled_slowdown)
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
        let mut rmt_buffer = [PulseCode::default(); NEOPIXEL_BUFFER_SIZE];
        let mut led = create_led_adapter(&mut ctx, &mut rmt_buffer);

        info!("LED red");
        write_color(&mut led, RGB8::new(255, 0, 0)).await;
        pause(RED_DISPLAY_DURATION).await;
        clear_led(&mut led).await;
    }

    #[test]
    async fn neopixel_rainbow(mut ctx: Context) {
        let mut rmt_buffer = [PulseCode::default(); NEOPIXEL_BUFFER_SIZE];
        let mut led = create_led_adapter(&mut ctx, &mut rmt_buffer);

        info!("rainbow cycle across 255 hues");
        for hue in 0u8..=254 {
            write_color(&mut led, rgb_from_hue(hue)).await;
            pause(rainbow_step_duration(hue)).await;
        }

        info!("final hue hold");
        write_color(&mut led, rgb_from_hue(FINAL_HUE)).await;
        pause(FINAL_HUE_DISPLAY_DURATION).await;
        clear_led(&mut led).await;
    }

    #[test]
    async fn neopixel_colors(mut ctx: Context) {
        let mut rmt_buffer = [PulseCode::default(); NEOPIXEL_BUFFER_SIZE];
        let mut led = create_led_adapter(&mut ctx, &mut rmt_buffer);

        for (color, name) in COLOR_SEQUENCE {
            info!("color: {}", name);
            write_color(&mut led, color).await;
            pause(COLOR_SEQUENCE_STEP_DURATION).await;
        }
        clear_led(&mut led).await;
    }
}
