#[cfg(dt = "labels::modem")]
pub mod cellular;

#[cfg(CONFIG_NET_DHCPV4_SERVER)]
pub mod dns;

#[cfg(CONFIG_NET_PKT_FILTER_IPV4_HOOK)]
pub mod nat;

pub mod wifi;

#[cfg(CONFIG_WIREGUARD)]
pub mod wireguard;
