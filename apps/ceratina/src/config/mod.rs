//! Device configuration — split by concern.
//!
//! - `board` — hardware truth: GPIO pins, bus wiring, sensor topology. Changes per PCB revision.
//! - `app` — deployment tuning: ports, timeouts, buffers, intervals. Changes per deployment.
//! - `features` — compile-time on/off switches for subsystems.

pub mod board;
pub mod app;
pub mod features;

const _: () = {
    assert!(
        board::i2c::BUS_0.sda_gpio != board::i2c::BUS_0.scl_gpio,
        "I2C bus 0: SDA and SCL must differ"
    );
    assert!(
        board::i2c::BUS_1.sda_gpio != board::i2c::BUS_1.scl_gpio,
        "I2C bus 1: SDA and SCL must differ"
    );
    assert!(app::ssh::PORT > 0, "Invalid SSH port");
    assert!(app::http::PORT > 0, "Invalid HTTP port");
    assert!(app::shell::BUF_IN >= 64, "Shell input buffer too small");
    assert!(app::shell::BUF_OUT >= 64, "Shell output buffer too small");
    assert!(board::buttons::COUNT <= 8, "Too many buttons");
};
