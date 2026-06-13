#![no_std]

pub mod boot;
pub mod filesystems;
pub mod networking;
pub mod services;
pub mod utils;

use log::{info, warn};
use zephyr::time::Duration;

#[cfg(dt = "labels::modem")]
use crate::{
    networking::{cellular, dns, nat, sntp, wifi},
    utils::errno::Errno,
};

#[cfg(not(dt = "labels::modem"))]
use crate::networking::wifi;

#[cfg(all(not(dt = "labels::modem"), CONFIG_WIREGUARD))]
use crate::networking::wireguard;

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }
    info!("rust_main on {}", zephyr::kconfig::CONFIG_BOARD);

    #[cfg(dt = "labels::modem")]
    router();

    #[cfg(not(dt = "labels::modem"))]
    node();

    if !boot::is_confirmed() {
        match boot::confirm() {
            Ok(()) => info!("boot: image confirmed"),
            Err(e) => warn!("boot confirm: {e}"),
        }
    }
}

#[cfg(dt = "labels::modem")]
fn router() {
    let bring_up_cellular_stack = || -> Result<(), Errno> {
        let timeout = Duration::millis(180_000);
        cellular::initialize()?;
        cellular::wait_for_attach(timeout)?;
        for (label, value) in cellular::access_identity().iter() {
            if !value.is_empty() {
                info!("{label}: {value}");
            }
        }
        nat::initialize()?;
        dns::initialize()?;
        match sntp::sync(
            core::ffi::CStr::from_bytes_with_nul(b"pool.ntp.org\0").unwrap(),
            5000,
        ) {
            Ok(()) => info!("sntp: time synced"),
            Err(e) => warn!("sntp: {e}"),
        }
        Ok(())
    };

    if let Err(e) = bring_up_cellular_stack() {
        warn!("cellular stack: {e}");
    }
    if let Err(e) = wifi::ap::enable(
        zephyr::kconfig::CONFIG_WIFI_CREDENTIALS_AP_SSID,
        wifi::DEFAULT_AP_PASSWORD,
    ) {
        warn!("wifi ap: {e}");
    }
}

#[cfg(not(dt = "labels::modem"))]
fn node() {
    if let Err(e) = wifi::sta::connect() {
        warn!("wifi sta: {e}");
    }
    match wifi::sta::wait_for_ipv4(Duration::secs(30)) {
        Ok(()) => {
            #[cfg(CONFIG_WIREGUARD)]
            if let Err(e) = wireguard::initialize() {
                warn!("wireguard: {e}");
            }
        }
        Err(e) => {
            warn!("wifi sta wait_for_ipv4: {e} — falling back to AP for provisioning");
            if let Err(e) = wifi::ap::enable(
                zephyr::kconfig::CONFIG_NET_HOSTNAME,
                wifi::DEFAULT_AP_PASSWORD,
            ) {
                warn!("wifi ap fallback: {e}");
            }
        }
    }
}
