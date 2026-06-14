set(mcuboot_EXTRA_CONF_FILE
  "${CMAKE_CURRENT_LIST_DIR}/src/boot/mcuboot.conf"
  CACHE INTERNAL ""
)

if(BOARD MATCHES "^walter")
  # Router role: upstream cellular + downstream WiFi-AP + NAT + DNS
  set(firmware_EXTRA_CONF_FILE
    "${CMAKE_CURRENT_LIST_DIR}/src/networking/pkt.conf"
    "${CMAKE_CURRENT_LIST_DIR}/src/networking/nat.conf"
    "${CMAKE_CURRENT_LIST_DIR}/src/networking/ppp.conf"
    "${CMAKE_CURRENT_LIST_DIR}/src/networking/modem.conf"
    "${CMAKE_CURRENT_LIST_DIR}/src/services/task_wdt.conf"
    CACHE INTERNAL ""
  )
elseif(BOARD MATCHES "^xiao_esp32s3")
  # Node role: WiFi STA + WireGuard underlay + AP fallback for provisioning
  set(firmware_EXTRA_CONF_FILE
    "${CMAKE_CURRENT_LIST_DIR}/src/networking/dns/mdns.conf"
    # NOTE: wireguard.conf out — vendor wg.c needs IPv6 cfg-gates
    # "${CMAKE_CURRENT_LIST_DIR}/src/networking/wireguard.conf"
    "${CMAKE_CURRENT_LIST_DIR}/src/security/mbedtls.conf"
    # NOTE: uncomment + add `-DDTC_OVERLAY_FILE=...halow.overlay` to use
    # "${CMAKE_CURRENT_LIST_DIR}/src/networking/halow/halow.conf"
    CACHE INTERNAL ""
  )
  set(firmware_SNIPPET espressif-flash-8M CACHE INTERNAL "")
endif()
