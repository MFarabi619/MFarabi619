use std::{
    ffi::{CString, NulError},
    fmt,
    os::raw::c_int,
};

pub(crate) mod ffi {
    use std::os::raw::{c_char, c_float, c_int};

    extern "C" {
        pub fn rgpiod_start(address: *const c_char, port: *const c_char) -> c_int;
        pub fn rgpiod_stop(sbc: c_int);
        pub fn gpiochip_open(sbc: c_int, device: c_int) -> c_int;
        pub fn gpiochip_close(sbc: c_int, handle: c_int) -> c_int;
        pub fn gpio_claim_output(
            sbc: c_int,
            handle: c_int,
            flags: c_int,
            gpio: c_int,
            value: c_int,
        ) -> c_int;
        pub fn gpio_write(sbc: c_int, handle: c_int, gpio: c_int, value: c_int) -> c_int;
        pub fn tx_pwm(
            sbc: c_int,
            handle: c_int,
            gpio: c_int,
            frequency: c_float,
            duty: c_float,
            offset: c_int,
            cycles: c_int,
        ) -> c_int;
        pub fn spi_open(
            sbc: c_int,
            device: c_int,
            channel: c_int,
            baud: c_int,
            flags: c_int,
        ) -> c_int;
        pub fn spi_close(sbc: c_int, handle: c_int) -> c_int;
        pub fn spi_write(sbc: c_int, handle: c_int, buf: *const c_char, count: c_int) -> c_int;
        pub fn i2c_open(sbc: c_int, i2c_bus: c_int, i2c_addr: c_int, i2c_flags: c_int) -> c_int;
        pub fn i2c_close(sbc: c_int, handle: c_int) -> c_int;
        pub fn i2c_write_byte_data(sbc: c_int, handle: c_int, reg: c_int, value: c_int) -> c_int;
        pub fn i2c_write_i2c_block_data(
            sbc: c_int,
            handle: c_int,
            reg: c_int,
            buf: *const c_char,
            count: c_int,
        ) -> c_int;
    }
}

#[derive(Debug)]
pub enum Error {
    Unreachable {
        host: String,
        port: u16,
    },
    HostContainsNul(NulError),
    Failed {
        operation: &'static str,
        code: c_int,
    },
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Unreachable { host, port } => {
                write!(f, "could not reach rgpiod at {host}:{port}")
            }
            Error::HostContainsNul(err) => write!(f, "host contains an interior nul byte: {err}"),
            Error::Failed { operation, code } => {
                write!(f, "{operation} failed with rgpio error {code}")
            }
        }
    }
}

impl std::error::Error for Error {}

pub(crate) fn check(operation: &'static str, code: c_int) -> Result<c_int, Error> {
    if code < 0 {
        Err(Error::Failed { operation, code })
    } else {
        Ok(code)
    }
}

pub struct Connection {
    pub(crate) sbc: c_int,
}

impl Connection {
    pub fn connect(host: &str, port: u16) -> Result<Self, Error> {
        let address = CString::new(host).map_err(Error::HostContainsNul)?;
        let port_string = CString::new(port.to_string()).expect("port digits have no nul");
        let sbc = unsafe { ffi::rgpiod_start(address.as_ptr(), port_string.as_ptr()) };
        if sbc < 0 {
            return Err(Error::Unreachable {
                host: host.to_string(),
                port,
            });
        }
        Ok(Self { sbc })
    }

    pub fn open_chip(&self, device: u32) -> Result<Chip<'_>, Error> {
        let handle = check("gpiochip_open", unsafe {
            ffi::gpiochip_open(self.sbc, device as c_int)
        })?;
        Ok(Chip {
            connection: self,
            handle,
        })
    }
}

impl Drop for Connection {
    fn drop(&mut self) {
        unsafe { ffi::rgpiod_stop(self.sbc) };
    }
}

pub struct Chip<'a> {
    connection: &'a Connection,
    handle: c_int,
}

impl Chip<'_> {
    pub fn claim_output(&self, gpio: u32, is_high: bool) -> Result<(), Error> {
        check("gpio_claim_output", unsafe {
            ffi::gpio_claim_output(
                self.connection.sbc,
                self.handle,
                0,
                gpio as c_int,
                is_high as c_int,
            )
        })
        .map(drop)
    }

    pub fn write(&self, gpio: u32, is_high: bool) -> Result<(), Error> {
        check("gpio_write", unsafe {
            ffi::gpio_write(
                self.connection.sbc,
                self.handle,
                gpio as c_int,
                is_high as c_int,
            )
        })
        .map(drop)
    }

    pub fn pwm(&self, gpio: u32, frequency_hz: f32, duty_percent: f32) -> Result<(), Error> {
        check("tx_pwm", unsafe {
            ffi::tx_pwm(
                self.connection.sbc,
                self.handle,
                gpio as c_int,
                frequency_hz,
                duty_percent,
                0,
                0,
            )
        })
        .map(drop)
    }
}

impl Drop for Chip<'_> {
    fn drop(&mut self) {
        unsafe { ffi::gpiochip_close(self.connection.sbc, self.handle) };
    }
}
