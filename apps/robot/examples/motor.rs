use std::{error::Error, thread::sleep, time::Duration};

use comfy_table::{
    modifiers, presets::UTF8_FULL, Attribute, Cell, Color, ContentArrangement, Table,
};
use robot::{
    config::{GPIO_CHIP, HOST, RGPIOD_PORT},
    hardware::{
        gpio::Connection,
        motor::{mix, Drivetrain, Motor, HALT},
    },
};

const LEFT_PWM_PIN: u32 = 12;
const LEFT_DIR_PIN: u32 = 6;
const RIGHT_PWM_PIN: u32 = 13;
const RIGHT_DIR_PIN: u32 = 5;
const LEFT_FORWARD_LEVEL: bool = true;
const RIGHT_FORWARD_LEVEL: bool = false;
const PWM_FREQUENCY_HZ: f32 = 10000.0;
const DIAGNOSTIC_DUTY: f32 = 40.0;
const DRIVE_MAGNITUDE: f64 = 0.8;
const HOLD: Duration = Duration::from_millis(1500);
const SETTLE: Duration = Duration::from_millis(1000);

fn config_table() -> Table {
    let mut table = Table::new();
    table
        .load_preset(UTF8_FULL)
        .apply_modifier(modifiers::UTF8_ROUND_CORNERS)
        .set_content_arrangement(ContentArrangement::Dynamic)
        .set_header(
            ["Side", "PWM pin", "DIR pin", "Forward level"]
                .into_iter()
                .map(|label| {
                    Cell::new(label)
                        .fg(Color::Cyan)
                        .add_attribute(Attribute::Bold)
                })
                .collect::<Vec<_>>(),
        );
    table.add_row(vec![
        Cell::new("left").fg(Color::Green),
        Cell::new(LEFT_PWM_PIN),
        Cell::new(LEFT_DIR_PIN),
        Cell::new(LEFT_FORWARD_LEVEL),
    ]);
    table.add_row(vec![
        Cell::new("right").fg(Color::Green),
        Cell::new(RIGHT_PWM_PIN),
        Cell::new(RIGHT_DIR_PIN),
        Cell::new(RIGHT_FORWARD_LEVEL),
    ]);
    table
}

fn movement_sequence() -> Result<(), Box<dyn Error>> {
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
        ("forward", mix(DRIVE_MAGNITUDE, 0.0)),
        ("backward", mix(-DRIVE_MAGNITUDE, 0.0)),
        ("turn left", mix(0.0, DRIVE_MAGNITUDE)),
        ("turn right", mix(0.0, -DRIVE_MAGNITUDE)),
    ];
    for (label, velocity) in movements {
        println!("  → {label}");
        drivetrain.drive(velocity)?;
        sleep(HOLD);
    }
    println!("  → stop");
    drivetrain.drive(HALT)?;
    Ok(())
}

fn dir_combination_sweep() -> Result<(), Box<dyn Error>> {
    let connection = Connection::connect(HOST, RGPIOD_PORT)?;
    let chip = connection.open_chip(GPIO_CHIP)?;
    for pin in [LEFT_PWM_PIN, LEFT_DIR_PIN, RIGHT_PWM_PIN, RIGHT_DIR_PIN] {
        chip.claim_output(pin, false)?;
    }

    let combinations = [
        ("both DIR low (left turn)", false, false),
        ("left DIR high, right DIR low (forward)", true, false),
        ("left DIR low, right DIR high (backward)", false, true),
        ("both DIR high (right turn)", true, true),
    ];
    for (label, left_high, right_high) in combinations {
        println!("  → {label}");
        chip.write(LEFT_DIR_PIN, left_high)?;
        chip.write(RIGHT_DIR_PIN, right_high)?;
        chip.pwm(LEFT_PWM_PIN, PWM_FREQUENCY_HZ, DIAGNOSTIC_DUTY)?;
        chip.pwm(RIGHT_PWM_PIN, PWM_FREQUENCY_HZ, DIAGNOSTIC_DUTY)?;
        sleep(HOLD);
        chip.pwm(LEFT_PWM_PIN, PWM_FREQUENCY_HZ, 0.0)?;
        chip.pwm(RIGHT_PWM_PIN, PWM_FREQUENCY_HZ, 0.0)?;
        sleep(SETTLE);
    }
    Ok(())
}

fn per_side_direction_sweep() -> Result<(), Box<dyn Error>> {
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
            let level = if direction_high { "high" } else { "low" };
            println!("  → {label} DIR={level}");
            chip.write(dir_pin, direction_high)?;
            chip.pwm(pwm_pin, PWM_FREQUENCY_HZ, DIAGNOSTIC_DUTY)?;
            sleep(HOLD);
            chip.pwm(pwm_pin, PWM_FREQUENCY_HZ, 0.0)?;
            sleep(SETTLE);
        }
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    println!("motor drive check");
    println!(
        "host {HOST}:{RGPIOD_PORT} · PWM {:.0} kHz · diagnostic duty {DIAGNOSTIC_DUTY:.0}% · drive speed {DRIVE_MAGNITUDE}",
        PWM_FREQUENCY_HZ / 1000.0
    );
    println!("{}", config_table());

    type Phase = (&'static str, fn() -> Result<(), Box<dyn Error>>);
    let phases: [Phase; 3] = [
        ("Movement sequence", movement_sequence),
        ("DIR combination sweep", dir_combination_sweep),
        ("Per-side direction sweep", per_side_direction_sweep),
    ];
    let total = phases.len();
    for (index, (name, run)) in phases.into_iter().enumerate() {
        println!("\n━━━ Phase {}/{total} · {name} ━━━", index + 1);
        run()?;
    }

    println!("\n✓ all phases complete");
    Ok(())
}
