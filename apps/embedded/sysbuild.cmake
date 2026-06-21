set(LIBS_FIRMWARE ${CMAKE_CURRENT_LIST_DIR}/../../libs/firmware)

set(mcuboot_EXTRA_CONF_FILE
  "${CMAKE_CURRENT_LIST_DIR}/mcuboot.conf"
  CACHE INTERNAL ""
)

set(_esp32s3_bundle
  "${CMAKE_CURRENT_LIST_DIR}/mcumgr.conf"

  "${LIBS_FIRMWARE}/programs/thread_analyzer.conf"

  "${LIBS_FIRMWARE}/debug.conf"
  "${LIBS_FIRMWARE}/programs/stats.conf"
  "${LIBS_FIRMWARE}/ram.conf"

  "${LIBS_FIRMWARE}/filesystems/nvs.conf"
  "${LIBS_FIRMWARE}/filesystems/img.conf"
  "${LIBS_FIRMWARE}/filesystems/zvfs.conf"
  "${LIBS_FIRMWARE}/filesystems/flash.conf"
  "${LIBS_FIRMWARE}/programs/settings.conf"

  "${LIBS_FIRMWARE}/networking/buf.conf"
  "${LIBS_FIRMWARE}/networking/ipv4.conf"
  "${LIBS_FIRMWARE}/networking/ipv6.conf"
  "${LIBS_FIRMWARE}/networking/net.conf"
  "${LIBS_FIRMWARE}/networking/sockets.conf"
  "${LIBS_FIRMWARE}/networking/hostname.conf"
  "${LIBS_FIRMWARE}/networking/statistics.conf"
  "${LIBS_FIRMWARE}/networking/dns/server.conf"
  "${LIBS_FIRMWARE}/networking/dns/resolver.conf"
  "${LIBS_FIRMWARE}/networking/dhcpv4.conf"
  "${LIBS_FIRMWARE}/networking/wifi.conf"
  "${LIBS_FIRMWARE}/networking/sntp.conf"

  "${LIBS_FIRMWARE}/services/mcumgr.conf"

  "${LIBS_FIRMWARE}/programs/hwinfo.conf"
  "${LIBS_FIRMWARE}/programs/gpio.conf"
)

if(BOARD MATCHES "^walter")
  set(embedded_EXTRA_CONF_FILE
    ${_esp32s3_bundle}
    "${LIBS_FIRMWARE}/networking/pkt.conf"
    "${LIBS_FIRMWARE}/networking/nat.conf"
    "${LIBS_FIRMWARE}/networking/ppp.conf"
    "${LIBS_FIRMWARE}/networking/modem.conf"
    "${LIBS_FIRMWARE}/services/task_wdt.conf"
    CACHE INTERNAL ""
  )
elseif(BOARD MATCHES "^xiao_esp32s3")
  set(_xiao_extra_conf
    ${_esp32s3_bundle}
    "${LIBS_FIRMWARE}/networking/dns/mdns.conf"
  )
  if(BOARD_QUALIFIERS MATCHES "sense")
    list(APPEND _xiao_extra_conf
      "${LIBS_FIRMWARE}/filesystems/fs.conf"
      "${LIBS_FIRMWARE}/services/http/http.conf"
    )
  endif()
  set(embedded_EXTRA_CONF_FILE "${_xiao_extra_conf}" CACHE INTERNAL "")
endif()
