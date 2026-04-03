//! SDHOST wiring probe for the ESP32-S3 board.
//!
//! `esp-hal` currently exposes the ESP32-S3 SDHOST peripheral in metadata/PAC,
//! but it does not provide a high-level SDHOST storage driver like it does for
//! SPI. This test therefore focuses on probing the most common ESP32-S3 SDMMC
//! pin candidates to see whether they look wired to an SD socket.

#![no_std]
#![no_main]

use defmt::info;
use esp_hal::{
    gpio::{Input, InputConfig, Pull},
    timer::timg::TimerGroup,
};

const SDHOST_COMMON_CLK_PIN: u32 = 36;
const SDHOST_COMMON_CMD_PIN: u32 = 35;
const SDHOST_COMMON_DATA0_PIN: u32 = 37;
const SDHOST_COMMON_DATA1_PIN: u32 = 38;
const SDHOST_COMMON_DATA2_PIN: u32 = 33;
const SDHOST_COMMON_DATA3_PIN: u32 = 34;

struct SdHostProbeResult {
    profile_name: &'static str,
    clk_is_high_with_pulldown: bool,
    cmd_is_high_with_pulldown: bool,
    data0_is_high_with_pulldown: bool,
    data1_is_high_with_pulldown: bool,
    data2_is_high_with_pulldown: bool,
    data3_is_high_with_pulldown: bool,
}

fn log_probe_result(probe_result: &SdHostProbeResult) {
    info!("SDHOST probe profile: {}", probe_result.profile_name);
    info!(
        "CLK GPIO{} pulled high externally: {}",
        SDHOST_COMMON_CLK_PIN,
        probe_result.clk_is_high_with_pulldown
    );
    info!(
        "CMD GPIO{} pulled high externally: {}",
        SDHOST_COMMON_CMD_PIN,
        probe_result.cmd_is_high_with_pulldown
    );
    info!(
        "D0  GPIO{} pulled high externally: {}",
        SDHOST_COMMON_DATA0_PIN,
        probe_result.data0_is_high_with_pulldown
    );
    info!(
        "D1  GPIO{} pulled high externally: {}",
        SDHOST_COMMON_DATA1_PIN,
        probe_result.data1_is_high_with_pulldown
    );
    info!(
        "D2  GPIO{} pulled high externally: {}",
        SDHOST_COMMON_DATA2_PIN,
        probe_result.data2_is_high_with_pulldown
    );
    info!(
        "D3  GPIO{} pulled high externally: {}",
        SDHOST_COMMON_DATA3_PIN,
        probe_result.data3_is_high_with_pulldown
    );
}

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::tests(executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[init]
    fn init() -> SdHostProbeResult {
        let peripherals = esp_hal::init(esp_hal::Config::default());

        let timer_group0 = TimerGroup::new(peripherals.TIMG0);
        esp_rtos::start(timer_group0.timer0);

        rtt_target::rtt_init_defmt!();

        let probe_input_config = InputConfig::default().with_pull(Pull::Down);

        let clock_input = Input::new(peripherals.GPIO36, probe_input_config);
        let command_input = Input::new(peripherals.GPIO35, probe_input_config);
        let data0_input = Input::new(peripherals.GPIO37, probe_input_config);
        let data1_input = Input::new(peripherals.GPIO38, probe_input_config);
        let data2_input = Input::new(peripherals.GPIO33, probe_input_config);
        let data3_input = Input::new(peripherals.GPIO34, probe_input_config);

        SdHostProbeResult {
            profile_name: "common ESP32-S3 SDMMC mapping",
            clk_is_high_with_pulldown: clock_input.is_high(),
            cmd_is_high_with_pulldown: command_input.is_high(),
            data0_is_high_with_pulldown: data0_input.is_high(),
            data1_is_high_with_pulldown: data1_input.is_high(),
            data2_is_high_with_pulldown: data2_input.is_high(),
            data3_is_high_with_pulldown: data3_input.is_high(),
        }
    }

    #[test]
    async fn probe_sdhost_candidate_pins(probe_result: SdHostProbeResult) {
        log_probe_result(&probe_result);

        info!(
            "Interpretation: CMD/D0-D3 reading high even with an internal pulldown suggests external SD pullups on those lines"
        );
        info!(
            "Interpretation: if these lines stay low, the socket is likely not wired to this common SDHOST pin set"
        );
    }
}
