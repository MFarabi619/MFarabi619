use log::{info, warn};
use zephyr::time::Duration;

use firmware::networking::{cellular, dns, nat, wifi};
use firmware::utils::errno::Errno;

pub fn run() {
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
