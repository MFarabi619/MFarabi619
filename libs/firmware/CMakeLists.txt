target_sources(app PRIVATE networking/wifi/wifi.c)

target_sources_ifdef(CONFIG_NVS app PRIVATE filesystems/flash_init_fix.c)

target_sources_ifdef(CONFIG_MODEM_CELLULAR app PRIVATE networking/cellular/cellular.c)

target_sources_ifdef(CONFIG_WIREGUARD app PRIVATE services/tailscale/tailscale.c)

target_sources_ifdef(CONFIG_NET_PKT_FILTER_IPV4_HOOK app PRIVATE
  networking/nat/nat.c
  networking/nat/conntrack.c
)

target_sources_ifdef(CONFIG_NET_DHCPV4_SERVER app PRIVATE
  networking/dns/proxy.c
)
set_source_files_properties(
  networking/dns/proxy.c
  PROPERTIES INCLUDE_DIRECTORIES "${ZEPHYR_BASE}/subsys/net/lib/dns"
)
