use crate::tasks::common::info;
use circular_buffer::CircularBuffer;
use colored_json::ToColoredJson;
use loco_rs::prelude::*;
use serde::{Deserialize, Serialize};
use serial::prelude::*;
use std::{io::Read, net::TcpStream, thread, time::Duration};
use vedirect_rs::get_vedirect_data;

const READ_SLEEP_MS: u64 = 150;

pub struct VeDirect;

#[derive(Debug, Deserialize)]
struct VeDirectSettings {
    input: String,
    output: Option<String>,
}

#[derive(Serialize)]
struct TimedSample<T> {
    time: String,
    #[serde(flatten)]
    data: T,
}

#[async_trait]
impl Task for VeDirect {
    fn task(&self) -> TaskInfo {
        TaskInfo {
            name: "ve-direct".into(),
            detail: "Stream VE.Direct frames as JSON".into(),
        }
    }

    async fn run(&self, app_context: &AppContext, _vars: &task::Vars) -> Result<()> {
        let ve_direct_settings = load_ve_direct_settings(app_context)?;
        let output_mode = ve_direct_settings.output.as_deref().unwrap_or("pretty");

        info("VE.Direct");
        info(&format!("input: {}", ve_direct_settings.input));
        info(&format!("output: {}", output_mode));

        if ve_direct_settings.input.starts_with("/dev/") {
            let serial_input = open_serial_device(&ve_direct_settings.input)?;
            stream_ve_direct_data(serial_input, output_mode)
        } else {
            let tcp_input = TcpStream::connect(&ve_direct_settings.input).map_err(|error| {
                Error::Message(format!(
                    "failed to connect to {}: {error}",
                    ve_direct_settings.input
                ))
            })?;

            stream_ve_direct_data(tcp_input, output_mode)
        }
    }
}

fn load_ve_direct_settings(app_context: &AppContext) -> Result<VeDirectSettings> {
    let settings_value = app_context
        .config
        .settings
        .as_ref()
        .ok_or_else(|| Error::Message("missing settings in config".into()))?;

    let ve_direct_value = settings_value
        .get("tasks")
        .and_then(|tasks| tasks.get("ve_direct"))
        .ok_or_else(|| Error::Message("missing settings.tasks.ve_direct in config".into()))?;

    serde_json::from_value(ve_direct_value.clone()).map_err(|error| {
        Error::Message(format!("failed to parse settings.tasks.ve_direct: {error}"))
    })
}

fn open_serial_device(device_path: &str) -> Result<impl Read> {
    let mut serial_port = serial::open(device_path)
        .map_err(|error| Error::Message(format!("failed to open {device_path}: {error}")))?;

    serial_port
        .reconfigure(&|settings| {
            settings.set_baud_rate(serial::Baud19200)?;
            settings.set_char_size(serial::Bits8);
            settings.set_parity(serial::ParityNone);
            settings.set_stop_bits(serial::Stop1);
            settings.set_flow_control(serial::FlowNone);
            Ok(())
        })
        .map_err(|error| Error::Message(format!("failed to configure {device_path}: {error}")))?;

    Ok(serial_port)
}

fn stream_ve_direct_data<InputReader: Read>(
    mut input_reader: InputReader,
    output_mode: &str,
) -> Result<()> {
    let mut stream_buffer = CircularBuffer::<4096, u8>::new();
    let mut read_buffer = [0; 256];

    loop {
        let bytes_read = input_reader
            .read(&mut read_buffer)
            .map_err(|error| Error::Message(format!("failed to read VE.Direct input: {error}")))?;

        if bytes_read == 0 {
            return Err(Error::Message("input closed".into()));
        }

        for &byte in &read_buffer[..bytes_read] {
            stream_buffer.push_back(byte);
        }

        if let Ok(parsed_blocks) = get_vedirect_data(stream_buffer.make_contiguous()) {
            stream_buffer.clear();

            for parsed_block in parsed_blocks {
                let timed_sample = TimedSample {
                    time: chrono::Local::now().to_rfc3339(),
                    data: parsed_block,
                };

                let json_output = match output_mode {
                    "pretty" => serde_json::to_string_pretty(&timed_sample)
                        .map_err(|error| Error::Message(format!("serialize error: {error}")))?
                        .to_colored_json_auto()
                        .map_err(|error| Error::Message(format!("color error: {error}")))?,
                    "compact" => serde_json::to_string(&timed_sample)
                        .map_err(|error| Error::Message(format!("serialize error: {error}")))?,
                    other => {
                        return Err(Error::Message(format!("invalid ve_direct.output: {other}")));
                    }
                };

                println!("{json_output}");
            }
        }

        thread::sleep(Duration::from_millis(READ_SLEEP_MS));
    }
}
