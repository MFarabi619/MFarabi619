use super::{
    App, FileSystemEntry, FileSystemLoadState, NetworkScanLoadState, WirelessNetworkEntry,
    WirelessStatus,
};

impl App {
    pub(super) fn apply_file_system_result(
        &mut self,
        fetch_result: Result<Vec<FileSystemEntry>, String>,
    ) {
        match fetch_result {
            Ok(file_system_entries) => {
                self.file_system_entries = file_system_entries;
                self.file_system_load_state = FileSystemLoadState::Loaded;
                #[cfg(not(target_arch = "wasm32"))]
                {
                    self.file_system_tree_state.select_first();
                }
            }
            Err(fetch_error) => {
                self.file_system_load_state = FileSystemLoadState::Error(fetch_error)
            }
        }
    }

    pub(super) fn apply_wireless_status_result(
        &mut self,
        fetch_result: Result<WirelessStatus, String>,
    ) {
        if let Ok(wireless_status) = fetch_result {
            self.wireless_status = Some(wireless_status);
        }
    }

    pub(super) fn apply_wireless_scan_result(
        &mut self,
        fetch_result: Result<Vec<WirelessNetworkEntry>, String>,
    ) {
        match fetch_result {
            Ok(wireless_networks) => {
                self.wireless_networks = wireless_networks;
                if self.wireless_networks.is_empty() {
                    self.network_table_state.select(None);
                } else if self.network_table_state.selected().is_none() {
                    self.network_table_state.select(Some(0));
                }
                self.network_scan_load_state = NetworkScanLoadState::Loaded;
            }
            Err(fetch_error) => {
                self.network_scan_load_state = NetworkScanLoadState::Error(fetch_error)
            }
        }
    }
}
