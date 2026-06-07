#[cfg(CONFIG_MODEM_CELLULAR)]
pub mod cellular;

pub mod dns;
pub mod nat;
pub mod wifi;
#[cfg(CONFIG_WIREGUARD)]
pub mod wireguard;
