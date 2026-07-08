use std::{thread::sleep, time::Duration};

use robot::hardware::{gpio::Connection, i2c::I2c, led::Led, pca9685::Pca9685};

const HOST: &str = "beagleyai";
const RGPIOD_PORT: u16 = 8889;
const I2C_BUS: u32 = 1;
const PCA9685_ADDRESS: u32 = 0x40;
const SERVO_CHANNELS: [u8; 3] = [0, 1, 2];
const CENTER_DEG: f64 = 90.0;
const SWEEP_DEG: [f64; 4] = [90.0, 0.0, 180.0, 90.0];
const SERVO_SETTLE: Duration = Duration::from_millis(500);

const PORT_CHIP: u32 = 3;
const PORT1_GPIO5_LINE: u32 = 15;
const PORT2_GPIO6_LINE: u32 = 17;
const PORT3_GPIO13_LINE: u32 = 18;
const LED_HOLD: Duration = Duration::from_millis(600);

#[test]
fn servos_sweep() -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::connect(HOST, RGPIOD_PORT)?;
    let i2c = I2c::open(&connection, I2C_BUS, PCA9685_ADDRESS)?;
    let pca9685 = Pca9685::new(i2c)?;

    for &channel in &SERVO_CHANNELS {
        pca9685.set_servo_angle(channel, CENTER_DEG)?;
    }
    sleep(SERVO_SETTLE);

    for &channel in &SERVO_CHANNELS {
        println!("servo channel {channel}");
        for angle in SWEEP_DEG {
            pca9685.set_servo_angle(channel, angle)?;
            sleep(SERVO_SETTLE);
        }
    }
    Ok(())
}

#[test]
fn port_leds() -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::connect(HOST, RGPIOD_PORT)?;
    let chip = connection.open_chip(PORT_CHIP)?;
    let leds = [
        ("port1 GPIO5", Led::new(&chip, PORT1_GPIO5_LINE)?),
        ("port2 GPIO6", Led::new(&chip, PORT2_GPIO6_LINE)?),
        ("port3 GPIO13", Led::new(&chip, PORT3_GPIO13_LINE)?),
    ];

    for (label, led) in &leds {
        println!("{label} on");
        led.on()?;
        sleep(LED_HOLD);
        led.off()?;
    }

    println!("all on");
    for (_, led) in &leds {
        led.on()?;
    }
    sleep(LED_HOLD);
    for (_, led) in &leds {
        led.off()?;
    }
    Ok(())
}

#[test]
fn servos_and_leds() -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::connect(HOST, RGPIOD_PORT)?;
    let i2c = I2c::open(&connection, I2C_BUS, PCA9685_ADDRESS)?;
    let pca9685 = Pca9685::new(i2c)?;
    let chip = connection.open_chip(PORT_CHIP)?;
    let leds = [
        Led::new(&chip, PORT1_GPIO5_LINE)?,
        Led::new(&chip, PORT2_GPIO6_LINE)?,
        Led::new(&chip, PORT3_GPIO13_LINE)?,
    ];

    for &channel in &SERVO_CHANNELS {
        pca9685.set_servo_angle(channel, CENTER_DEG)?;
    }
    sleep(SERVO_SETTLE);

    for (&channel, led) in SERVO_CHANNELS.iter().zip(&leds) {
        println!("channel {channel}");
        led.on()?;
        for angle in SWEEP_DEG {
            pca9685.set_servo_angle(channel, angle)?;
            sleep(SERVO_SETTLE);
        }
        led.off()?;
    }
    Ok(())
}
