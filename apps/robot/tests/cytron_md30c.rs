use std::{thread::sleep, time::Duration};

use robot::hardware::{
    gpio::Connection,
    motor::{mix, Drivetrain, Motor, HALT},
};

const HOST: &str = "rpi5-16-2";
const RGPIOD_PORT: u16 = 8889;
const GPIO_CHIP: u32 = 0;
const LEFT_PWM_PIN: u32 = 12;
const LEFT_DIR_PIN: u32 = 6;
const RIGHT_PWM_PIN: u32 = 13;
const RIGHT_DIR_PIN: u32 = 5;
const LEFT_FORWARD_LEVEL: bool = true;
const RIGHT_FORWARD_LEVEL: bool = false;
const PWM_FREQUENCY_HZ: f32 = 1000.0;
const DIAGNOSTIC_DUTY: f32 = 40.0;
const SPEED: f64 = 0.8;
const HOLD: Duration = Duration::from_millis(1500);
const SETTLE: Duration = Duration::from_millis(1000);

#[test]
fn motors_run_movement_sequence() -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::connect(HOST, RGPIOD_PORT)?;
    let chip = connection.open_chip(GPIO_CHIP)?;
    let drivetrain = Drivetrain::new(
        Motor::pwm_dir(
            &chip,
            LEFT_DIR_PIN,
            LEFT_PWM_PIN,
            LEFT_FORWARD_LEVEL,
            PWM_FREQUENCY_HZ,
        )?,
        Motor::pwm_dir(
            &chip,
            RIGHT_DIR_PIN,
            RIGHT_PWM_PIN,
            RIGHT_FORWARD_LEVEL,
            PWM_FREQUENCY_HZ,
        )?,
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

#[test]
fn motor_directions_sweep() -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::connect(HOST, RGPIOD_PORT)?;
    let chip = connection.open_chip(GPIO_CHIP)?;
    for pin in [LEFT_PWM_PIN, LEFT_DIR_PIN, RIGHT_PWM_PIN, RIGHT_DIR_PIN] {
        chip.claim_output(pin, false)?;
    }

    let sides = [
        ("left", LEFT_DIR_PIN, LEFT_PWM_PIN),
        ("right", RIGHT_DIR_PIN, RIGHT_PWM_PIN),
    ];
    for (label, dir_pin, pwm_pin) in sides {
        for direction_high in [false, true] {
            println!(
                "{label} DIR={}",
                if direction_high { "high" } else { "low" }
            );
            chip.write(dir_pin, direction_high)?;
            chip.pwm(pwm_pin, PWM_FREQUENCY_HZ, DIAGNOSTIC_DUTY)?;
            sleep(HOLD);
            chip.pwm(pwm_pin, PWM_FREQUENCY_HZ, 0.0)?;
            sleep(SETTLE);
        }
    }
    Ok(())
}
