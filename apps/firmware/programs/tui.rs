use alloc::{vec, vec::Vec};
use core::convert::Infallible;
use core::sync::atomic::{AtomicBool, AtomicI32, Ordering};

use embedded_graphics::{
    pixelcolor::{raw::ToBytes, Rgb565},
    prelude::*,
    primitives::Rectangle,
};
use mousefood::{EmbeddedBackend, EmbeddedBackendConfig, fonts};
use ratatui::Terminal;
use zephyr::raw::{
    INPUT_ABS_X, INPUT_ABS_Y, INPUT_BTN_TOUCH, INPUT_EV_ABS, INPUT_EV_KEY, __device_dts_ord_24,
    __device_dts_ord_49, __device_dts_ord_53, device, display_blanking_off,
    display_buffer_descriptor, display_capabilities, display_get_capabilities, display_write,
    input_callback, input_event, k_msleep, led_off, led_set_brightness, sys_reboot,
};

use crate::ui::{self, Action, TouchState};

const _: () = assert!(zephyr::devicetree::labels::ili9341::ORD == 24);
const _: () = assert!(zephyr::devicetree::pwmleds::ORD == 49);
const _: () = assert!(zephyr::devicetree::labels::pwmleds_backlight::ORD == 53);

const SYS_REBOOT_COLD: i32 = 1;

static TOUCH_X: AtomicI32 = AtomicI32::new(-1);
static TOUCH_Y: AtomicI32 = AtomicI32::new(-1);
static TOUCH_PRESSED: AtomicBool = AtomicBool::new(false);

unsafe extern "C" fn on_touch(evt: *mut input_event, _user: *mut core::ffi::c_void) {
    let evt = unsafe { &*evt };
    let t = evt.type_ as u32;
    let c = evt.code as u32;
    if t == INPUT_EV_ABS {
        if c == INPUT_ABS_X {
            TOUCH_X.store(evt.value, Ordering::Relaxed);
        } else if c == INPUT_ABS_Y {
            TOUCH_Y.store(evt.value, Ordering::Relaxed);
        }
    } else if t == INPUT_EV_KEY && c == INPUT_BTN_TOUCH {
        TOUCH_PRESSED.store(evt.value != 0, Ordering::Relaxed);
    }
}

// Hand-rolled iterable-section entry equivalent to INPUT_CALLBACK_DEFINE.
// Section name reconstructed from STRUCT_SECTION_ITERABLE expansion:
// `._<struct_type>.static.<varname>_` per zephyr/sys/iterable_sections.h.
// dev = NULL → receives events from all input devices.
#[repr(transparent)]
struct InputCallbackEntry(input_callback);
unsafe impl Sync for InputCallbackEntry {}

#[link_section = "._input_callback.static._input_callback__touch_"]
#[used]
static TOUCH_CB: InputCallbackEntry = InputCallbackEntry(input_callback {
    dev: core::ptr::null(),
    callback: Some(on_touch),
    user_data: core::ptr::null_mut(),
});

fn display_device() -> *const device {
    unsafe { &__device_dts_ord_24 as *const device }
}

fn led_device() -> *const device {
    unsafe { &__device_dts_ord_49 as *const device }
}

fn backlight_device() -> *const device {
    unsafe { &__device_dts_ord_53 as *const device }
}

pub struct ZephyrDisplay {
    dev: *const device,
    width: u16,
    height: u16,
    row_buf: Vec<u8>,
}

unsafe impl Send for ZephyrDisplay {}

impl ZephyrDisplay {
    pub fn new(dev: *const device, width: u16, height: u16) -> Self {
        let row_buf = vec![0u8; width as usize * 2];
        Self {
            dev,
            width,
            height,
            row_buf,
        }
    }

    fn blit_row(&mut self, x: u16, y: u16, w: u16) {
        let desc = display_buffer_descriptor {
            buf_size: (w as u32) * 2,
            width: w,
            height: 1,
            pitch: w,
            frame_incomplete: false,
        };
        unsafe {
            display_write(self.dev, x, y, &desc, self.row_buf.as_ptr() as *const _);
        }
    }
}

impl OriginDimensions for ZephyrDisplay {
    fn size(&self) -> Size {
        Size::new(self.width as u32, self.height as u32)
    }
}

impl DrawTarget for ZephyrDisplay {
    type Color = Rgb565;
    type Error = Infallible;

    fn draw_iter<I>(&mut self, pixels: I) -> Result<(), Self::Error>
    where
        I: IntoIterator<Item = Pixel<Self::Color>>,
    {
        for Pixel(coord, color) in pixels {
            if coord.x < 0
                || coord.y < 0
                || coord.x >= self.width as i32
                || coord.y >= self.height as i32
            {
                continue;
            }
            let bytes = color.to_be_bytes();
            self.row_buf[0] = bytes[0];
            self.row_buf[1] = bytes[1];
            let desc = display_buffer_descriptor {
                buf_size: 2,
                width: 1,
                height: 1,
                pitch: 1,
                frame_incomplete: false,
            };
            unsafe {
                display_write(
                    self.dev,
                    coord.x as u16,
                    coord.y as u16,
                    &desc,
                    self.row_buf.as_ptr() as *const _,
                );
            }
        }
        Ok(())
    }

    fn fill_contiguous<I>(&mut self, area: &Rectangle, colors: I) -> Result<(), Self::Error>
    where
        I: IntoIterator<Item = Self::Color>,
    {
        let bb = self.bounding_box();
        let area = area.intersection(&bb);
        if area.size.width == 0 || area.size.height == 0 {
            return Ok(());
        }
        let w = area.size.width as u16;
        let h = area.size.height as u16;
        let x = area.top_left.x as u16;
        let y = area.top_left.y as u16;

        let mut iter = colors.into_iter();
        for row in 0..h {
            for col in 0..(w as usize) {
                let color = iter.next().unwrap_or(Rgb565::BLACK);
                let bytes = color.to_be_bytes();
                self.row_buf[col * 2] = bytes[0];
                self.row_buf[col * 2 + 1] = bytes[1];
            }
            self.blit_row(x, y + row, w);
        }
        Ok(())
    }
}

pub fn display_loop() {
    let dev = display_device();

    let blanking_rc = unsafe { display_blanking_off(dev) };
    if blanking_rc != 0 {
        log::warn!("ui: display_blanking_off rc={}", blanking_rc);
    }

    let bl_rc = unsafe { led_set_brightness(backlight_device(), 0, 100) };
    if bl_rc != 0 {
        log::warn!("ui: led_set_brightness(backlight) rc={}", bl_rc);
    }

    let mut caps: display_capabilities = unsafe { core::mem::zeroed() };
    unsafe { display_get_capabilities(dev, &mut caps) };

    let mut display = ZephyrDisplay::new(dev, caps.x_resolution, caps.y_resolution);
    let _ = display.clear(Rgb565::BLACK);

    let backend = EmbeddedBackend::new(
        &mut display,
        EmbeddedBackendConfig {
            font_regular: fonts::mono_10x20_atlas(),
            ..Default::default()
        },
    );
    let mut terminal = match Terminal::new(backend) {
        Ok(t) => t,
        Err(e) => {
            log::error!("ui: Terminal::new failed: {e}");
            return;
        }
    };

    let mut touch = TouchState::new();

    loop {
        touch.pressed = TOUCH_PRESSED.load(Ordering::Relaxed);
        touch.x = TOUCH_X.load(Ordering::Relaxed);
        touch.y = TOUCH_Y.load(Ordering::Relaxed);

        let mut action: Option<Action> = None;
        let _ = terminal.draw(|frame| {
            action = ui::render_app(frame, &touch);
        });
        touch.commit();

        match action {
            Some(Action::LedOff) => {
                log::info!("ui: LED OFF tapped");
                unsafe {
                    let _ = led_off(led_device(), 0);
                    let _ = led_off(led_device(), 1);
                    let _ = led_off(led_device(), 2);
                }
            }
            Some(Action::Reboot) => {
                log::info!("ui: REBOOT tapped");
                unsafe { sys_reboot(SYS_REBOOT_COLD) };
            }
            None => {}
        }

        unsafe {
            k_msleep(33);
        }
    }
}
