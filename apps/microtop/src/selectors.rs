use crate::app::{App, NetworkScanLoadState};

pub fn access_point_ip_text(app: &App) -> String {
    app.wireless_status
        .as_ref()
        .map(|wireless_status| wireless_status.ap_ipv4.clone())
        .unwrap_or_else(|| "0.0.0.0".to_owned())
}

pub fn network_scan_status_text(app: &App) -> String {
    match &app.network_scan_load_state {
        NetworkScanLoadState::Idle => "Idle".to_owned(),
        NetworkScanLoadState::Loading => "Scanning...".to_owned(),
        NetworkScanLoadState::Loaded => format!("Found {} network(s)", app.wireless_networks.len()),
        NetworkScanLoadState::Error(error_message) => format!("Error: {error_message}"),
    }
}

pub fn connected_network_identity(app: &App) -> (Option<String>, String) {
    let connected_ssid = app
        .wireless_status
        .as_ref()
        .filter(|wireless_status| wireless_status.connected)
        .map(|wireless_status| wireless_status.sta_ssid.clone());

    let connected_station_ip = app
        .wireless_status
        .as_ref()
        .filter(|wireless_status| wireless_status.connected)
        .map(|wireless_status| wireless_status.sta_ipv4.clone())
        .unwrap_or_default();

    (connected_ssid, connected_station_ip)
}
