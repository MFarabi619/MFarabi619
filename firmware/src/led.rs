use core::ptr::addr_of_mut;
use zephyr::raw::*;

const BRIGHTNESS: u8 = 20;

static mut PIXELS: [led_rgb; 1] = [led_rgb { r: 0, g: 0, b: 0 }];

pub struct Color(pub u8, pub u8, pub u8);

pub const BLACK: Color = Color(0, 0, 0);
pub const GREEN: Color = Color(0, 128, 0);
pub const YELLOW: Color = Color(255, 255, 0);

pub fn init() {
    set(BLACK);
}

pub fn set(c: Color) {
    unsafe {
        let strip = zr_device_get_led_strip();
        if strip.is_null() {
            return;
        }
        let px = addr_of_mut!(PIXELS) as *mut led_rgb;
        (*px).r = (c.0 as u16 * BRIGHTNESS as u16 / 255) as u8;
        (*px).g = (c.1 as u16 * BRIGHTNESS as u16 / 255) as u8;
        (*px).b = (c.2 as u16 * BRIGHTNESS as u16 / 255) as u8;
        led_strip_update_rgb(strip, px, 1);
    }
}
