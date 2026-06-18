set(LIBS_FIRMWARE ${CMAKE_CURRENT_LIST_DIR}/../../libs/firmware)

set(mcuboot_EXTRA_CONF_FILE
  "${CMAKE_CURRENT_LIST_DIR}/mcuboot.conf"
  CACHE INTERNAL ""
)

if(BOARD MATCHES "^walter")
  # Router role: upstream cellular + downstream WiFi-AP + NAT + DNS
  set(embedded_SNIPPET "espressif-flash-16M;espressif-psram-2M;espressif-psram-wifi;wifi-credentials" CACHE INTERNAL "")
  set(embedded_EXTRA_CONF_FILE
    "${LIBS_FIRMWARE}/networking/pkt.conf"
    "${LIBS_FIRMWARE}/networking/nat.conf"
    "${LIBS_FIRMWARE}/networking/ppp.conf"
    "${LIBS_FIRMWARE}/networking/modem.conf"
    "${LIBS_FIRMWARE}/services/task_wdt.conf"
    CACHE INTERNAL ""
  )
elseif(BOARD MATCHES "^xiao_esp32s3")
  # Node role: WiFi STA + WireGuard underlay + AP fallback for provisioning
  set(_xiao_extra_conf
    "${LIBS_FIRMWARE}/networking/dns/mdns.conf"
    # NOTE: wireguard.conf out — vendor wg.c needs IPv6 cfg-gates
    # "${LIBS_FIRMWARE}/networking/wireguard.conf"
    # NOTE: uncomment + add `-DDTC_OVERLAY_FILE=libs/firmware/halow/halow.overlay` to use
    # "${LIBS_FIRMWARE}/halow/halow.conf"
  )
  if(BOARD_QUALIFIERS MATCHES "sense")
    list(APPEND _xiao_extra_conf
      "${LIBS_FIRMWARE}/filesystems/fs.conf"
      "${LIBS_FIRMWARE}/services/mcumgr_fs.conf"
      "${LIBS_FIRMWARE}/services/http/http.conf"
    )
  endif()
  set(embedded_EXTRA_CONF_FILE "${_xiao_extra_conf}" CACHE INTERNAL "")
  # NOTE: espressif-psram-reloc skipped — OCT PSRAM + 40M flash (WREN workaround)
  # interact badly with boot-time .text/.rodata copy from flash; shell hangs.
  set(embedded_SNIPPET "espressif-flash-8M;espressif-psram-wifi;wifi-credentials" CACHE INTERNAL "")
endif()
