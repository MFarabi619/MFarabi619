#[cfg(dt = "labels::modem")]
pub mod cellular;

#[cfg(CONFIG_NET_DHCPV4_SERVER)]
pub mod dns;

pub mod wifi;

#[cfg(CONFIG_WIREGUARD)]
pub mod wireguard;
