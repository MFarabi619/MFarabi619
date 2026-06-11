target_sources(app PRIVATE networking/wifi/wifi.c)

target_include_directories(app PRIVATE ${ZEPHYR_BASE}/subsys/net/ip)

target_sources_ifdef(CONFIG_NET_PKT_FILTER_IPV4_HOOK app PRIVATE
  networking/nat/nat.c
  networking/nat/conntrack.c
)

target_sources_ifdef(CONFIG_NET_DHCPV4_SERVER app PRIVATE
  networking/dns/proxy.c
)

target_sources_ifdef(CONFIG_SNTP app PRIVATE networking/sntp.c)
target_sources_ifdef(CONFIG_NVS app PRIVATE filesystems/flash_init_fix.c)
target_sources_ifdef(CONFIG_MODEM_CELLULAR app PRIVATE networking/cellular/cellular.c)

target_sources_ifdef(CONFIG_WIREGUARD app PRIVATE networking/wireguard/wireguard.c)
if(CONFIG_WIREGUARD)
  target_include_directories(app PRIVATE ${ZEPHYR_BASE}/subsys/net/lib/wireguard)
endif()

set_source_files_properties(
  networking/dns/proxy.c
  PROPERTIES INCLUDE_DIRECTORIES "${ZEPHYR_BASE}/subsys/net/lib/dns"
)

# NOTE: uncomment wolfssl/wolfssh projects in west.yml + add services/ssh/wolfssh.conf + boot/posix.conf to app's EXTRA_CONF_FILE
# if(CONFIG_WOLFSSH)
#   zephyr_include_directories(${CMAKE_CURRENT_SOURCE_DIR}/services/ssh)
# endif()
