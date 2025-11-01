#![no_std]
#![no_main]
#![deny(
    clippy::mem_forget,
    reason = "mem::forget is generally not safe to do with esp_hal types, especially those \
    holding buffers for the duration of a data transfer."
)]

use {
    bt_hci::controller::ExternalController,
    defmt::info,
    embassy_executor::Spawner,
    embassy_time::{Duration, Timer},
    esp_hal::{
        clock::CpuClock,
        timer::{systimer::SystemTimer, timg::TimerGroup},
    },
    esp_wifi::{
        ble::controller::BleConnector,
        wifi::{ClientConfiguration, Configuration},
    },
    embassy_net::{
        self as net, tcp::TcpSocket, Config as NetConfig, IpAddress, IpEndpoint, Stack,
        StackResources,
    },
    static_cell::StaticCell,
    alloc::{boxed::Box, string::String},
    esp_backtrace as _,
    esp_println as _,
};

extern crate alloc;

esp_bootloader_esp_idf::esp_app_desc!();

const SERVER_PORT: u16 = 80;
const RX_BUF_SIZE: usize = 1024;
const TX_BUF_SIZE: usize = 1024;
const TRASH_BUF_SIZE: usize = 512;

static NET_RESOURCES: StaticCell<StackResources<3>> = StaticCell::new();

#[embassy_executor::task]
async fn net_task(mut runner: net::Runner<'static, esp_wifi::wifi::WifiDevice<'static>>) -> ! {
    runner.run().await
}

fn fmt_ip(ep: Option<IpEndpoint>) -> heapless::String<64> {
    match ep {
        Some(IpEndpoint { addr: IpAddress::Ipv4(v4), .. }) => {
            let [a, b, c, d] = v4.octets();
            let mut s = heapless::String::<64>::new();
            let _ = core::fmt::write(&mut s, format_args!("{a}.{b}.{c}.{d}"));
            s
        }
        _ => {
            let mut s = heapless::String::<64>::new();
            let _ = s.push_str("unknown");
            s
        }
    }
}

fn build_body(ip: &str) -> heapless::String<512> {
    let mut s = heapless::String::<512>::new();
    let _ = core::fmt::write(
        &mut s,
        format_args!(
            concat!(
                "<!doctype html>",
                "<meta charset='utf-8'>",
                "<meta name='viewport' content='width=device-width,initial-scale=1'>",
                "<title>ESP32 Hello</title>",
                "<h1>ESP32 says hi 👋</h1>",
                "<p>Your IP: <b>{}</b></p>"
            ),
            ip
        ),
    );
    s
}

fn build_headers(len: usize) -> heapless::String<128> {
    let mut s = heapless::String::<128>::new();
    let _ = core::fmt::write(
        &mut s,
        format_args!(
            "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            len
        ),
    );
    s
}

#[embassy_executor::task]
async fn http_server(stack: Stack<'static>) {
    info!("HTTP server listening on :80");
    let mut rx_buf = [0u8; RX_BUF_SIZE];
    let mut tx_buf = [0u8; TX_BUF_SIZE];

    loop {
        let mut sock = TcpSocket::new(stack, &mut rx_buf, &mut tx_buf);
        if let Err(e) = sock.accept(SERVER_PORT).await {
            info!("accept error: {:?}", defmt::Debug2Format(&e));
            continue;
        }

        let ip_str = fmt_ip(sock.remote_endpoint());
        info!("HTTP connection from {}", ip_str.as_str());

        let mut trash = [0u8; TRASH_BUF_SIZE];
        if let Err(e) = sock.read(&mut trash).await {
            info!("read request error: {:?}", defmt::Debug2Format(&e));
        }

        let body = build_body(ip_str.as_str());
        let headers = build_headers(body.len());

        if let Err(e) = sock.write(headers.as_bytes()).await {
            info!("write headers error: {:?}", defmt::Debug2Format(&e));
        }
        if let Err(e) = sock.write(body.as_bytes()).await {
            info!("write body error: {:?}", defmt::Debug2Format(&e));
        }
        if let Err(e) = sock.flush().await {
            info!("flush error: {:?}", defmt::Debug2Format(&e));
        }
        sock.close();
    }
}

#[esp_hal_embassy::main]
async fn main(spawner: Spawner) {
    let peripherals = esp_hal::init(esp_hal::Config::default().with_cpu_clock(CpuClock::max()));
    esp_alloc::heap_allocator!(size: 64 * 1024);
    esp_alloc::heap_allocator!(#[unsafe(link_section = ".dram2_uninit")] size: 64 * 1024);
    esp_hal_embassy::init(SystemTimer::new(peripherals.SYSTIMER).alarm0);
    info!("Embassy initialized!");

    let WIFI_SSID = option_env!("WIFI_SSID").unwrap_or("IT HURTS WHEN IP");
    let WIFI_PSK = option_env!("WIFI_PSK").unwrap_or("PASSWORD");

    let mut rng = esp_hal::rng::Rng::new(peripherals.RNG);
    let wifi_init = Box::leak(Box::new(
        esp_wifi::init(TimerGroup::new(peripherals.TIMG0).timer0, rng)
            .expect("Failed to initialize WIFI/BLE controller"),
    ));

    let (mut wifi_controller, interfaces) =
        esp_wifi::wifi::new(&*wifi_init, peripherals.WIFI).expect("Failed to initialize WIFI controller");
    let _ble_controller = ExternalController::<_, 20>::new(BleConnector::new(&*wifi_init, peripherals.BT));

    let ssid: String = WIFI_SSID.into();
    let password: String = WIFI_PSK.into();
    wifi_controller
        .set_configuration(&Configuration::Client(ClientConfiguration { ssid, password, ..Default::default() }))
        .expect("wifi set_configuration failed");
    wifi_controller.start().expect("wifi start failed");
    wifi_controller.connect().expect("wifi connect failed");

    while !wifi_controller.is_connected().unwrap_or(false) {
        Timer::after(Duration::from_millis(250)).await;
    }

    info!("WiFi connected");

    let resources = NET_RESOURCES.init(StackResources::<3>::new());
    let seed: u64 = ((rng.random() as u64) << 32) | (rng.random() as u64);
    let (stack, runner) = net::new(interfaces.sta, NetConfig::dhcpv4(Default::default()), resources, seed);
    let stack_for_log = stack;

    spawner.spawn(net_task(runner)).ok();
    spawner.spawn(http_server(stack)).expect("spawn http_server");

    let mut uptime_s: u64 = 0;

    loop {
        let connected = wifi_controller.is_connected().unwrap_or(false);
        let ip = stack_for_log.config_v4().map(|c| c.address.address().octets());
        match ip {
            Some([a, b, c, d]) => info!(
                "WiFi | ssid: '{}' | connected: {} | ip: {}.{}.{}.{} | uptime: {}s",
                WIFI_SSID, connected, a, b, c, d, uptime_s
            ),
            None => info!(
                "WiFi | ssid: '{}' | connected: {} | ip: 0.0.0.0 | uptime: {}s",
                WIFI_SSID, connected, uptime_s
            ),
        }

        uptime_s += 1;
        Timer::after(Duration::from_secs(1)).await;
    }
}
