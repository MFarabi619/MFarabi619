use alloc::{vec, vec::Vec};
use core::convert::Infallible;

use embedded_graphics::{
    pixelcolor::{raw::ToBytes, Rgb565},
    prelude::*,
    primitives::Rectangle,
};
use mousefood::{fonts, EmbeddedBackend, EmbeddedBackendConfig};
use ratatui::{
    style::*,
    widgets::{Block, Paragraph, Wrap},
    Frame, Terminal,
};
use zephyr::raw::{
    __device_dts_ord_118, device, display_blanking_off, display_buffer_descriptor,
    display_capabilities, display_get_capabilities, display_write, k_msleep,
};

const _: () = assert!(zephyr::devicetree::labels::ili9341::ORD == 118);

fn display_device() -> *const device {
    unsafe { &__device_dts_ord_118 as *const device }
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

    loop {
        let _ = terminal.draw(draw);
        unsafe {
            k_msleep(33);
        }
    }
}

fn draw(frame: &mut Frame) {
    let text = "Ratatui on embedded devices!";
    let paragraph = Paragraph::new(text.dark_gray()).wrap(Wrap { trim: true });
    let bordered_block = Block::bordered()
        .border_style(Style::new().yellow())
        .title("Mousefood");
    frame.render_widget(paragraph.block(bordered_block), frame.area());
}
