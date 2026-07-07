use std::os::raw::{c_char, c_int};

use super::gpio::{check, ffi, Connection, Error};

pub struct Spi<'a> {
    connection: &'a Connection,
    handle: c_int,
}

impl<'a> Spi<'a> {
    pub fn open(
        connection: &'a Connection,
        device: u32,
        channel: u32,
        clock_hz: u32,
        mode: u32,
    ) -> Result<Self, Error> {
        let handle = check("spi_open", unsafe {
            ffi::spi_open(
                connection.sbc,
                device as c_int,
                channel as c_int,
                clock_hz as c_int,
                mode as c_int,
            )
        })?;
        Ok(Self { connection, handle })
    }

    pub fn write(&self, bytes: &[u8]) -> Result<(), Error> {
        check("spi_write", unsafe {
            ffi::spi_write(
                self.connection.sbc,
                self.handle,
                bytes.as_ptr() as *const c_char,
                bytes.len() as c_int,
            )
        })
        .map(drop)
    }
}

impl Drop for Spi<'_> {
    fn drop(&mut self) {
        unsafe { ffi::spi_close(self.connection.sbc, self.handle) };
    }
}
