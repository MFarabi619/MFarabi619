#[cfg(not(target_arch = "wasm32"))]
use {
    super::{
        ApiEnvelope, App, FileSystemEntry, FileSystemLoadState, NativeBackgroundMessage,
        NetworkScanLoadState, WirelessScanData, WirelessStatus,
    },
    reqwest::blocking::Client,
    serde::de::DeserializeOwned,
    std::{
        sync::mpsc::{Sender, TryRecvError},
        thread,
    },
};

#[cfg(not(target_arch = "wasm32"))]
impl App {
    pub fn start_initial_load_native(&mut self) {
        self.start_file_system_refresh_native();
        self.start_wireless_status_refresh_native();
        self.start_network_scan_native();
    }

    pub fn poll_native_background_messages(&mut self) {
        loop {
            match self.native_background_receiver.try_recv() {
                Ok(native_background_message) => match native_background_message {
                    NativeBackgroundMessage::FileSystem(fetch_result) => {
                        self.apply_file_system_result(fetch_result)
                    }
                    NativeBackgroundMessage::WirelessStatus(fetch_result) => {
                        self.apply_wireless_status_result(fetch_result)
                    }
                    NativeBackgroundMessage::WirelessScan(fetch_result) => {
                        self.apply_wireless_scan_result(fetch_result)
                    }
                },
                Err(TryRecvError::Empty) | Err(TryRecvError::Disconnected) => break,
            }
        }
    }

    fn spawn_native_get_json<T>(
        endpoint: String,
        native_background_sender: Sender<NativeBackgroundMessage>,
        error_context: &'static str,
        map_message: fn(Result<T, String>) -> NativeBackgroundMessage,
    ) where
        T: DeserializeOwned + Send + 'static,
    {
        thread::spawn(move || {
            let fetch_result = Client::new()
                .get(endpoint)
                .send()
                .and_then(|response| response.error_for_status())
                .and_then(|response| response.json::<T>())
                .map_err(|error| format!("{error_context} request failed: {error}"));
            let _ = native_background_sender.send(map_message(fetch_result));
        });
    }

    fn spawn_native_post_json<T>(
        endpoint: String,
        native_background_sender: Sender<NativeBackgroundMessage>,
        error_context: &'static str,
        map_message: fn(Result<T, String>) -> NativeBackgroundMessage,
    ) where
        T: DeserializeOwned + Send + 'static,
    {
        thread::spawn(move || {
            let fetch_result = Client::new()
                .post(endpoint)
                .send()
                .and_then(|response| response.error_for_status())
                .and_then(|response| response.json::<T>())
                .map_err(|error| format!("{error_context} request failed: {error}"));
            let _ = native_background_sender.send(map_message(fetch_result));
        });
    }

    pub fn start_file_system_refresh_native(&mut self) {
        if matches!(self.file_system_load_state, FileSystemLoadState::Loading) {
            return;
        }
        self.file_system_load_state = FileSystemLoadState::Loading;
        Self::spawn_native_get_json::<Vec<FileSystemEntry>>(
            self.endpoint("/api/filesystem/list"),
            self.native_background_sender.clone(),
            "filesystem",
            NativeBackgroundMessage::FileSystem,
        );
    }

    pub fn start_wireless_status_refresh_native(&mut self) {
        Self::spawn_native_get_json::<ApiEnvelope<WirelessStatus>>(
            self.endpoint("/api/wireless/status"),
            self.native_background_sender.clone(),
            "wireless status",
            |fetch_result| {
                NativeBackgroundMessage::WirelessStatus(fetch_result.map(|envelope| envelope.data))
            },
        );
    }

    pub fn start_network_scan_native(&mut self) {
        if matches!(self.network_scan_load_state, NetworkScanLoadState::Loading) {
            return;
        }
        self.network_scan_load_state = NetworkScanLoadState::Loading;
        Self::spawn_native_post_json::<ApiEnvelope<WirelessScanData>>(
            self.endpoint("/api/wireless/actions/scan"),
            self.native_background_sender.clone(),
            "wireless scan",
            |fetch_result| {
                NativeBackgroundMessage::WirelessScan(
                    fetch_result.map(|envelope| envelope.data.networks),
                )
            },
        );
    }
}
