#![no_std]
#![no_main]

extern crate alloc;

use defmt::info;
use embassy_net::{Runner, StackResources};
use embassy_time::{Duration, Timer, with_timeout};
use esp_hal::{clock::CpuClock, peripherals::WIFI, rng::Rng, timer::timg::TimerGroup};
use esp_radio::wifi::{ClientConfig, ModeConfig, WifiController, WifiDevice, WifiEvent};
use static_cell::StaticCell;

const WIFI_SSID: &str = env!("NETWORK_WIFI_SSID");
const WIFI_PASSWORD: &str = env!("NETWORK_WIFI_PSK");

macro_rules! mk_static {
    ($type:ty, $value:expr) => {{
        static STATIC_CELL: StaticCell<$type> = StaticCell::new();
        STATIC_CELL.uninit().write($value)
    }};
}

struct Context {
    wifi: WIFI<'static>,
}

fn client_mode_config() -> ModeConfig {
    ModeConfig::Client(
        ClientConfig::default()
            .with_ssid(WIFI_SSID.into())
            .with_password(WIFI_PASSWORD.into()),
    )
}

fn random_seed(random_number_generator: &mut Rng) -> u64 {
    (u64::from(random_number_generator.random()) << 32)
        | u64::from(random_number_generator.random())
}

esp_bootloader_esp_idf::esp_app_desc!();

#[cfg(test)]
#[embedded_test::tests(default_timeout = 45, executor = esp_rtos::embassy::Executor::new())]
mod tests {
    use super::*;

    #[embassy_executor::task]
    async fn connection_task(mut wifi_controller: WifiController<'static>) {
        loop {
            info!("attempting Wi-Fi connection");

            match wifi_controller.connect_async().await {
                Ok(()) => {
                    info!("Wi-Fi connected");
                    wifi_controller
                        .wait_for_event(WifiEvent::StaDisconnected)
                        .await;
                    info!("Wi-Fi disconnected");
                }
                Err(error) => {
                    info!("Wi-Fi connect failed: {:?}", error);
                    Timer::after(Duration::from_secs(2)).await;
                }
            }
        }
    }

    #[embassy_executor::task]
    async fn net_task(mut runner: Runner<'static, WifiDevice<'static>>) {
        runner.run().await;
    }

    #[init]
    fn init() -> Context {
        let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
        let peripherals = esp_hal::init(config);

        esp_alloc::heap_allocator!(#[esp_hal::ram(reclaimed)] size: 64 * 1024);
        esp_alloc::heap_allocator!(size: 64 * 1024);

        let timer_group0 = TimerGroup::new(peripherals.TIMG0);
        esp_rtos::start(timer_group0.timer0);

        rtt_target::rtt_init_defmt!();

        info!("Wi-Fi DHCP test initialized");

        Context {
            wifi: peripherals.WIFI,
        }
    }

    #[test]
    #[timeout(30)]
    async fn gets_ipv4_address_over_dhcp(context: Context) {
        let spawner = unsafe { embassy_executor::Spawner::for_current_executor().await };

        let radio_controller =
            mk_static!(esp_radio::Controller<'static>, esp_radio::init().unwrap());

        let (mut wifi_controller, interfaces) =
            esp_radio::wifi::new(radio_controller, context.wifi, Default::default()).unwrap();

        let mode_config = client_mode_config();
        wifi_controller.set_config(&mode_config).unwrap();
        wifi_controller.start_async().await.unwrap();

        let mut random_number_generator = Rng::new();
        let seed = random_seed(&mut random_number_generator);
        let network_config = embassy_net::Config::dhcpv4(Default::default());
        let (stack, runner) = embassy_net::new(
            interfaces.sta,
            network_config,
            mk_static!(StackResources<3>, StackResources::<3>::new()),
            seed,
        );

        spawner.spawn(connection_task(wifi_controller)).unwrap();
        spawner.spawn(net_task(runner)).unwrap();

        with_timeout(Duration::from_secs(25), stack.wait_config_up())
            .await
            .unwrap();

        let ipv4_config = stack.config_v4().unwrap();
        info!("DHCP address acquired: {}", ipv4_config.address);
    }
}
