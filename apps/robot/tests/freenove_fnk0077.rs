use std::{thread::sleep, time::Duration};

use robot::hardware::{
    gpio::Connection,
    motor::{mix, Drivetrain, Motor, HALT},
    ws2812::{LedStrip, BLUE, GREEN, OFF, RED, WHITE},
};

const HOST: &str = "rpi5-16";
const RGPIOD_PORT: u16 = 8889;
const SPEED: f64 = 0.5;
const HOLD: Duration = Duration::from_millis(1500);

const WIPE_WAIT: Duration = Duration::from_millis(50);
const CHASE_WAIT: Duration = Duration::from_millis(50);
const RAINBOW_WAIT: Duration = Duration::from_millis(20);

#[test]
fn leds_run_animations() -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::connect(HOST, RGPIOD_PORT)?;
    let mut leds = LedStrip::open(&connection)?;

    println!("index: red / green / blue / white");
    leds.set(0, RED)?;
    leds.set(1, GREEN)?;
    leds.set(2, BLUE)?;
    leds.set(3, WHITE)?;
    sleep(Duration::from_secs(3));

    println!("color wipe: red, green, blue");
    leds.color_wipe(RED, WIPE_WAIT)?;
    leds.color_wipe(GREEN, WIPE_WAIT)?;
    leds.color_wipe(BLUE, WIPE_WAIT)?;
    sleep(Duration::from_secs(1));

    println!("theater chase rainbow");
    leds.theater_chase_rainbow(CHASE_WAIT)?;
    println!("rainbow");
    leds.rainbow(RAINBOW_WAIT, 1)?;
    println!("rainbow cycle");
    leds.rainbow_cycle(RAINBOW_WAIT, 1)?;

    println!("off");
    leds.color_wipe(OFF, WIPE_WAIT)?;
    Ok(())
}

#[test]
fn motors_run_movement_sequence() -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::connect(HOST, RGPIOD_PORT)?;
    let chip = connection.open_chip(0)?;
    let drivetrain = Drivetrain::new(
        Motor::dual_pwm(&chip, 24, 23, 1000.0)?,
        Motor::dual_pwm(&chip, 5, 6, 1000.0)?,
    );

    let movements = [
        ("forward", mix(SPEED, 0.0)),
        ("backward", mix(-SPEED, 0.0)),
        ("turn left", mix(0.0, SPEED)),
        ("turn right", mix(0.0, -SPEED)),
    ];
    for (label, velocity) in movements {
        println!("{label}");
        drivetrain.drive(velocity)?;
        sleep(HOLD);
    }
    println!("stop");
    drivetrain.drive(HALT)?;
    Ok(())
}
