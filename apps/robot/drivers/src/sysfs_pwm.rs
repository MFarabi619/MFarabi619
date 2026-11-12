use std::{
    fs,
    io::{Seek, SeekFrom, Write},
    path::{Path, PathBuf},
    thread,
    time::Duration,
};

use crate::motor::{DriveCommand, WheelDrive};

pub const PULSE_PERIOD_NANOSECONDS: i64 = 20_000_000;
pub const PULSE_NEUTRAL_NANOSECONDS: i64 = 1_500_000;
pub const PULSE_HALF_RANGE_NANOSECONDS: i64 = 500_000;
const PWM_EXPORT_MAX_ATTEMPTS: u32 = 500;
const EXPORT_RETRY_DELAY: Duration = Duration::from_millis(10);

pub struct PulseChannel {
    channel_directory: PathBuf,
    duty_file: fs::File,
    is_reversed: bool,
    last_pulse_nanoseconds: i64,
}

impl PulseChannel {
    pub fn new(
        sysfs_root: &Path,
        chip: u32,
        channel: u32,
        is_reversed: bool,
    ) -> std::io::Result<Self> {
        let chip_directory = sysfs_root.join(format!("pwmchip{chip}"));
        let channel_directory = chip_directory.join(format!("pwm{channel}"));
        if !channel_directory.exists() {
            fs::write(chip_directory.join("export"), channel.to_string())?;
        }
        let duty_path = channel_directory.join("duty_cycle");
        let mut duty_file = open_when_writable(&duty_path)?;
        duty_file.write_all(b"0")?;
        duty_file.flush()?;
        fs::write(
            channel_directory.join("period"),
            PULSE_PERIOD_NANOSECONDS.to_string(),
        )?;
        fs::write(channel_directory.join("enable"), "1")?;
        let mut pulse_channel = Self {
            channel_directory,
            duty_file,
            is_reversed,
            last_pulse_nanoseconds: 0,
        };
        pulse_channel.halt()?;
        Ok(pulse_channel)
    }

    pub fn drive(&mut self, fraction: f64) -> std::io::Result<f64> {
        let fraction = fraction.clamp(-1.0, 1.0);
        let applied = if self.is_reversed { -fraction } else { fraction };
        self.write_pulse_nanoseconds(
            PULSE_NEUTRAL_NANOSECONDS + (applied * PULSE_HALF_RANGE_NANOSECONDS as f64) as i64,
        )?;
        Ok(fraction)
    }

    pub fn halt(&mut self) -> std::io::Result<()> {
        self.write_pulse_nanoseconds(PULSE_NEUTRAL_NANOSECONDS)
    }

    fn write_pulse_nanoseconds(&mut self, pulse_nanoseconds: i64) -> std::io::Result<()> {
        if pulse_nanoseconds == self.last_pulse_nanoseconds {
            return Ok(());
        }
        self.duty_file.seek(SeekFrom::Start(0))?;
        self.duty_file
            .write_all(pulse_nanoseconds.to_string().as_bytes())?;
        self.duty_file.flush()?;
        self.last_pulse_nanoseconds = pulse_nanoseconds;
        Ok(())
    }
}

impl Drop for PulseChannel {
    fn drop(&mut self) {
        let _ = self.halt();
        let _ = fs::write(self.channel_directory.join("enable"), "0");
    }
}

pub struct PulseDrivetrain {
    left: PulseChannel,
    right: PulseChannel,
    max_speed_meters_per_second: f64,
}

impl PulseDrivetrain {
    pub fn new(left: PulseChannel, right: PulseChannel, max_speed_meters_per_second: f64) -> Self {
        Self {
            left,
            right,
            max_speed_meters_per_second,
        }
    }
}

impl WheelDrive for PulseDrivetrain {
    fn drive(
        &mut self,
        command: DriveCommand,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        self.left
            .drive(command.left / self.max_speed_meters_per_second)?;
        self.right
            .drive(command.right / self.max_speed_meters_per_second)?;
        Ok(())
    }
}

fn open_when_writable(duty_path: &Path) -> std::io::Result<fs::File> {
    let mut attempts = 0;
    loop {
        match fs::OpenOptions::new().write(true).open(duty_path) {
            Ok(file) => return Ok(file),
            Err(error) => {
                attempts += 1;
                if attempts >= PWM_EXPORT_MAX_ATTEMPTS {
                    return Err(error);
                }
                thread::sleep(EXPORT_RETRY_DELAY);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake_channel(root: &Path, chip: u32, channel: u32) {
        let channel_directory = root.join(format!("pwmchip{chip}/pwm{channel}"));
        fs::create_dir_all(&channel_directory).unwrap();
        for attribute in ["duty_cycle", "period", "enable"] {
            fs::write(channel_directory.join(attribute), "").unwrap();
        }
    }

    fn fake_sysfs(test_name: &str) -> PathBuf {
        let root = std::env::temp_dir()
            .join("robot_sysfs_pwm_tests")
            .join(format!("{}_{}", std::process::id(), test_name));
        fake_channel(&root, 2, 1);
        root
    }

    fn read_channel_attribute(root: &Path, chip: u32, channel: u32, attribute: &str) -> String {
        fs::read_to_string(root.join(format!("pwmchip{chip}/pwm{channel}")).join(attribute))
            .unwrap()
    }

    fn read_attribute(root: &Path, attribute: &str) -> String {
        read_channel_attribute(root, 2, 1, attribute)
    }

    #[test]
    fn configures_channel_and_parks_at_neutral() {
        let root = fake_sysfs("configure");
        let _channel = PulseChannel::new(&root, 2, 1, false).unwrap();
        assert_eq!(
            read_attribute(&root, "period"),
            PULSE_PERIOD_NANOSECONDS.to_string()
        );
        assert_eq!(read_attribute(&root, "enable"), "1");
        assert_eq!(
            read_attribute(&root, "duty_cycle"),
            PULSE_NEUTRAL_NANOSECONDS.to_string()
        );
    }

    #[test]
    fn full_forward_and_reverse_hit_pulse_band_edges() {
        let root = fake_sysfs("band_edges");
        let mut channel = PulseChannel::new(&root, 2, 1, false).unwrap();
        channel.drive(1.0).unwrap();
        assert_eq!(read_attribute(&root, "duty_cycle"), "2000000");
        channel.drive(-1.0).unwrap();
        assert_eq!(read_attribute(&root, "duty_cycle"), "1000000");
    }

    #[test]
    fn reversed_channel_flips_pulse_direction() {
        let root = fake_sysfs("reversed");
        let mut channel = PulseChannel::new(&root, 2, 1, true).unwrap();
        channel.drive(0.5).unwrap();
        assert_eq!(read_attribute(&root, "duty_cycle"), "1250000");
    }

    #[test]
    fn drive_reports_clamped_fraction() {
        let root = fake_sysfs("clamp");
        let mut channel = PulseChannel::new(&root, 2, 1, false).unwrap();
        assert_eq!(channel.drive(2.5).unwrap(), 1.0);
        assert_eq!(read_attribute(&root, "duty_cycle"), "2000000");
    }

    #[test]
    fn drivetrain_scales_wheel_speeds_into_pulse_band() {
        let root = fake_sysfs("drivetrain");
        fake_channel(&root, 0, 0);
        fake_channel(&root, 0, 1);
        let mut drivetrain = PulseDrivetrain::new(
            PulseChannel::new(&root, 0, 0, false).unwrap(),
            PulseChannel::new(&root, 0, 1, false).unwrap(),
            2.0,
        );
        drivetrain
            .drive(DriveCommand {
                left: 2.0,
                right: -1.0,
            })
            .unwrap();
        assert_eq!(read_channel_attribute(&root, 0, 0, "duty_cycle"), "2000000");
        assert_eq!(read_channel_attribute(&root, 0, 1, "duty_cycle"), "1250000");
    }

    #[test]
    fn drop_disables_channel_at_neutral() {
        let root = fake_sysfs("drop");
        {
            let mut channel = PulseChannel::new(&root, 2, 1, false).unwrap();
            channel.drive(1.0).unwrap();
        }
        assert_eq!(read_attribute(&root, "enable"), "0");
        assert_eq!(
            read_attribute(&root, "duty_cycle"),
            PULSE_NEUTRAL_NANOSECONDS.to_string()
        );
    }
}
