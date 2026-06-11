#![no_std]

use log::{info, warn};
use zephyr::time::Duration;

use firmware::boot;

#[cfg(CONFIG_MODEM_CELLULAR)]
use firmware::{
    networking::{cellular, dns, nat, wifi},
    utils::errno::Errno,
};

#[cfg(not(CONFIG_MODEM_CELLULAR))]
use firmware::networking::{wifi, wireguard};

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        zephyr::set_logger().unwrap();
    }
    info!("rust_main on {}", zephyr::kconfig::CONFIG_BOARD);

    #[cfg(CONFIG_MODEM_CELLULAR)]
    walter();

    #[cfg(not(CONFIG_MODEM_CELLULAR))]
    xiao();

    if !boot::is_confirmed() {
        match boot::confirm() {
            Ok(()) => info!("boot: image confirmed"),
            Err(e) => warn!("boot confirm: {e}"),
        }
    }
}

#[cfg(CONFIG_MODEM_CELLULAR)]
fn walter() {
    if let Err(e) = bring_up_cellular_stack() {
        warn!("cellular stack: {e}");
    }
    if let Err(e) = wifi::ap::enable(
        zephyr::kconfig::CONFIG_WIFI_CREDENTIALS_AP_SSID,
        zephyr::kconfig::CONFIG_WIFI_CREDENTIALS_AP_PASSWORD,
    ) {
        warn!("wifi ap: {e}");
    }
}

#[cfg(CONFIG_MODEM_CELLULAR)]
fn bring_up_cellular_stack() -> Result<(), Errno> {
    let timeout = Duration::millis(zephyr::kconfig::CONFIG_CELLULAR_ATTACH_TIMEOUT_MS as u64);
    cellular::initialize()?;
    cellular::wait_for_attach(timeout)?;
    for (label, value) in cellular::access_identity().iter() {
        if !value.is_empty() {
            info!("{label}: {value}");
        }
    }
    if let Err(e) = cellular::initialize_callbacks() {
        warn!("cellular: registration init failed: {e}");
    }
    nat::initialize()?;
    dns::initialize()?;
    Ok(())
}

#[cfg(not(CONFIG_MODEM_CELLULAR))]
fn xiao() {
    if let Err(e) = wifi::sta::connect() {
        warn!("wifi sta: {e}");
    }
    match wifi::sta::wait_for_ipv4(Duration::secs(30)) {
        Ok(()) => {
            if let Err(e) = wireguard::initialize() {
                warn!("wireguard: {e}");
            }
        }
        Err(e) => {
            warn!("wifi sta wait_for_ipv4: {e} — falling back to AP for provisioning");
            if let Err(e) = wifi::ap::enable(
                zephyr::kconfig::CONFIG_WIFI_CREDENTIALS_AP_SSID,
                zephyr::kconfig::CONFIG_WIFI_CREDENTIALS_AP_PASSWORD,
            ) {
                warn!("wifi ap fallback: {e}");
            }
        }
    }
}
