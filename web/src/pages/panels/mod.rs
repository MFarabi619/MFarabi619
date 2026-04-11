pub mod bluetooth_panel;
pub mod csv;
pub mod filesystem_panel;
pub mod flash_panel;
pub mod measurement_panel;
pub mod network_panel;
pub mod sensor_feed;
pub mod sensor_types;
pub mod shared_ui;
pub mod terminal_panel;

pub use bluetooth_panel::BluetoothPanel;
pub use csv::*;
pub use filesystem_panel::FilesystemPanel;
pub use flash_panel::FlashPanel;
pub use measurement_panel::MeasurementPanel;
pub use network_panel::NetworkPanel;
pub use terminal_panel::TerminalPanel;
pub use sensor_feed::*;
pub use sensor_types::*;
pub use shared_ui::*;

pub fn now_time_string() -> String {
    js_sys::Date::new_0().to_locale_time_string("en-US").into()
}

pub async fn sleep_ms(milliseconds: u32) {
    #[cfg(target_arch = "wasm32")]
    gloo_timers::future::TimeoutFuture::new(milliseconds).await;
    #[cfg(not(target_arch = "wasm32"))]
    {
        let _ = milliseconds;
        std::future::pending::<()>().await;
    }
}
