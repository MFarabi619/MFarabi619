use std::{thread::sleep, time::Duration};

use robot::config::{GPIO_CHIP, HOST, I2C_BUS, PCA9685_ADDRESS, RGPIOD_PORT};
use robot_drivers::{gpio::Connection, i2c::I2c, led::Led, pca9685::Pca9685};

const SERVO_CHANNELS: [u8; 3] = [0, 1, 2];
const CENTER_DEG: f64 = 90.0;
const SWEEP_DEG: [f64; 4] = [90.0, 0.0, 180.0, 90.0];
const SERVO_SETTLE: Duration = Duration::from_millis(500);

const PORT1_GPIO5: u32 = 5;
const PORT2_GPIO6: u32 = 6;
const PORT3_GPIO13: u32 = 13;
const LED_HOLD: Duration = Duration::from_millis(600);

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

fn port_leds() -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::connect(HOST, RGPIOD_PORT)?;
    let chip = connection.open_chip(GPIO_CHIP)?;
    let leds = [
        ("port1 GPIO5", Led::new(&chip, PORT1_GPIO5)?),
        ("port2 GPIO6", Led::new(&chip, PORT2_GPIO6)?),
        ("port3 GPIO13", Led::new(&chip, PORT3_GPIO13)?),
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

fn servos_and_leds() -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::connect(HOST, RGPIOD_PORT)?;
    let i2c = I2c::open(&connection, I2C_BUS, PCA9685_ADDRESS)?;
    let pca9685 = Pca9685::new(i2c)?;
    let chip = connection.open_chip(GPIO_CHIP)?;
    let leds = [
        Led::new(&chip, PORT1_GPIO5)?,
        Led::new(&chip, PORT2_GPIO6)?,
        Led::new(&chip, PORT3_GPIO13)?,
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

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("━━━ servo sweep ━━━");
    servos_sweep()?;
    println!("━━━ port LEDs ━━━");
    port_leds()?;
    println!("━━━ servos + LEDs ━━━");
    servos_and_leds()?;
    Ok(())
}
