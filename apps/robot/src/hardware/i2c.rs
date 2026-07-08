use std::os::raw::{c_char, c_int};

use super::gpio::{check, ffi, Connection, Error};

pub struct I2c<'a> {
    connection: &'a Connection,
    handle: c_int,
}

impl<'a> I2c<'a> {
    pub fn open(connection: &'a Connection, bus: u32, address: u32) -> Result<Self, Error> {
        let handle = check("i2c_open", unsafe {
            ffi::i2c_open(connection.sbc, bus as c_int, address as c_int, 0)
        })?;
        Ok(Self { connection, handle })
    }

    pub fn write_byte(&self, register: u8, value: u8) -> Result<(), Error> {
        check("i2c_write_byte_data", unsafe {
            ffi::i2c_write_byte_data(
                self.connection.sbc,
                self.handle,
                register as c_int,
                value as c_int,
            )
        })
        .map(drop)
    }

    pub fn write_block(&self, register: u8, bytes: &[u8]) -> Result<(), Error> {
        check("i2c_write_i2c_block_data", unsafe {
            ffi::i2c_write_i2c_block_data(
                self.connection.sbc,
                self.handle,
                register as c_int,
                bytes.as_ptr() as *const c_char,
                bytes.len() as c_int,
            )
        })
        .map(drop)
    }
}

impl Drop for I2c<'_> {
    fn drop(&mut self) {
        unsafe { ffi::i2c_close(self.connection.sbc, self.handle) };
    }
}
