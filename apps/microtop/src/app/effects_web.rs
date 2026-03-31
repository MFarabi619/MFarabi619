#[cfg(target_arch = "wasm32")]
use {
    super::{
        ApiEnvelope, App, FileSystemEntry, FileSystemLoadState, NetworkScanLoadState,
        WirelessScanData, WirelessStatus,
    },
    gloo_net::http::Request,
    std::{cell::RefCell, rc::Rc},
    wasm_bindgen_futures::spawn_local,
};

#[cfg(target_arch = "wasm32")]
impl App {
    async fn parse_web_json_response<T>(
        response: gloo_net::http::Response,
        error_context: &'static str,
    ) -> Result<T, String>
    where
        T: serde::de::DeserializeOwned,
    {
        if !response.ok() {
            return Err(format!(
                "{error_context} request failed with status {}",
                response.status()
            ));
        }

        response
            .json::<T>()
            .await
            .map_err(|error| format!("{error_context} JSON decode failed: {error}"))
    }

    pub fn start_initial_load_web(application_state: Rc<RefCell<Self>>) {
        Self::start_file_system_refresh_web(application_state.clone());
        Self::start_wireless_status_refresh_web(application_state.clone());
        Self::start_network_scan_web(application_state);
    }

    pub fn start_file_system_refresh_web(application_state: Rc<RefCell<Self>>) {
        let endpoint = {
            let mut app = application_state.borrow_mut();
            if matches!(app.file_system_load_state, FileSystemLoadState::Loading) {
                return;
            }
            app.file_system_load_state = FileSystemLoadState::Loading;
            app.endpoint("/api/filesystem/list")
        };

        spawn_local(async move {
            let fetch_result = match Request::get(&endpoint).send().await {
                Ok(response) => {
                    Self::parse_web_json_response::<Vec<FileSystemEntry>>(response, "filesystem")
                        .await
                }
                Err(fetch_error) => Err(format!("filesystem request failed: {fetch_error}")),
            };
            application_state
                .borrow_mut()
                .apply_file_system_result(fetch_result);
        });
    }

    pub fn start_wireless_status_refresh_web(application_state: Rc<RefCell<Self>>) {
        let endpoint = application_state.borrow().endpoint("/api/wireless/status");
        spawn_local(async move {
            let fetch_result = match Request::get(&endpoint).send().await {
                Ok(response) => Self::parse_web_json_response::<ApiEnvelope<WirelessStatus>>(
                    response,
                    "wireless status",
                )
                .await
                .map(|api_envelope| api_envelope.data),
                Err(fetch_error) => Err(format!("wireless status request failed: {fetch_error}")),
            };
            application_state
                .borrow_mut()
                .apply_wireless_status_result(fetch_result);
        });
    }

    pub fn start_network_scan_web(application_state: Rc<RefCell<Self>>) {
        let endpoint = {
            let mut app = application_state.borrow_mut();
            if matches!(app.network_scan_load_state, NetworkScanLoadState::Loading) {
                return;
            }
            app.network_scan_load_state = NetworkScanLoadState::Loading;
            app.endpoint("/api/wireless/actions/scan")
        };

        spawn_local(async move {
            let fetch_result = match Request::post(&endpoint).send().await {
                Ok(response) => Self::parse_web_json_response::<ApiEnvelope<WirelessScanData>>(
                    response,
                    "wireless scan",
                )
                .await
                .map(|api_envelope| api_envelope.data.networks),
                Err(fetch_error) => Err(format!("wireless scan request failed: {fetch_error}")),
            };
            application_state
                .borrow_mut()
                .apply_wireless_scan_result(fetch_result);
        });
    }
}
