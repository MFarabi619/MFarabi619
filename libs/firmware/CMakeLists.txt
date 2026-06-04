target_sources(app PRIVATE networking/wifi.c)

target_sources_ifdef(CONFIG_NET_PKT_FILTER_IPV4_HOOK app PRIVATE
  networking/nat/nat.c
  networking/nat/conntrack.c
)

target_sources_ifdef(CONFIG_DNS_RESOLVER app PRIVATE
  networking/dns_proxy.c
)
set_source_files_properties(
  networking/dns_proxy.c
  PROPERTIES INCLUDE_DIRECTORIES "${ZEPHYR_BASE}/subsys/net/lib/dns"
)
