use core::cell::UnsafeCell;
use core::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use zephyr::raw::*;

const BRIGHTNESS: u8 = 20;

struct PixelBuffer {
    inner: UnsafeCell<[led_rgb; 1]>,
}

unsafe impl Sync for PixelBuffer {}

static PIXELS: PixelBuffer = PixelBuffer {
    inner: UnsafeCell::new([led_rgb { r: 0, g: 0, b: 0 }]),
};

static IS_ON: AtomicBool = AtomicBool::new(false);
static LAST_REQUESTED_COLOR: AtomicU32 = AtomicU32::new(0x00FFFFFF);

#[derive(Clone, Copy)]
pub struct Color(pub u8, pub u8, pub u8);

pub const BLACK: Color = Color(0, 0, 0);
pub const GREEN: Color = Color(0, 128, 0);
pub const YELLOW: Color = Color(255, 255, 0);
pub const MAGENTA: Color = Color(255, 0, 255);

fn pack(c: Color) -> u32 {
    ((c.0 as u32) << 16) | ((c.1 as u32) << 8) | (c.2 as u32)
}

fn unpack(value: u32) -> Color {
    Color(
        ((value >> 16) & 0xFF) as u8,
        ((value >> 8) & 0xFF) as u8,
        (value & 0xFF) as u8,
    )
}

pub fn init() {
    set(BLACK);
}

pub fn set(c: Color) {
    let is_lit = c.0 != 0 || c.1 != 0 || c.2 != 0;
    if is_lit {
        LAST_REQUESTED_COLOR.store(pack(c), Ordering::Relaxed);
    }
    IS_ON.store(is_lit, Ordering::Relaxed);
    write_hardware(c);
}

pub fn set_color(red: u8, green: u8, blue: u8) {
    set(Color(red, green, blue));
}

pub fn turn_on() {
    let color = unpack(LAST_REQUESTED_COLOR.load(Ordering::Relaxed));
    set(color);
}

pub fn turn_off() {
    IS_ON.store(false, Ordering::Relaxed);
    write_hardware(BLACK);
}

pub fn is_on() -> bool {
    IS_ON.load(Ordering::Relaxed)
}

pub fn current_color() -> Color {
    if is_on() {
        unpack(LAST_REQUESTED_COLOR.load(Ordering::Relaxed))
    } else {
        BLACK
    }
}

fn write_hardware(c: Color) {
    unsafe {
        let strip = zr_device_get_led_strip();
        if strip.is_null() {
            return;
        }
        let pixel = (*PIXELS.inner.get()).as_mut_ptr();
        (*pixel).r = (c.0 as u16 * BRIGHTNESS as u16 / 255) as u8;
        (*pixel).g = (c.1 as u16 * BRIGHTNESS as u16 / 255) as u8;
        (*pixel).b = (c.2 as u16 * BRIGHTNESS as u16 / 255) as u8;
        led_strip_update_rgb(strip, pixel, 1);
    }
}
