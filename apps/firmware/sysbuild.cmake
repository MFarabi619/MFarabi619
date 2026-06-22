if(BOARD MATCHES "^esp32s3" OR BOARD MATCHES "^xiao_esp32s3" OR BOARD MATCHES "^walter")
  file(GLOB espressif_openocd_installs LIST_DIRECTORIES true
    "$ENV{HOME}/.espressif/tools/openocd-esp32/*/openocd-esp32")
  if(espressif_openocd_installs)
    list(GET espressif_openocd_installs 0 espressif_openocd_dir)
    get_filename_component(espressif_toolchain_root "${espressif_openocd_dir}" DIRECTORY)
    set(ESPRESSIF_TOOLCHAIN_PATH "${espressif_toolchain_root}" CACHE PATH "" FORCE)
    set(OPENOCD "${espressif_openocd_dir}/bin/openocd" CACHE FILEPATH "" FORCE)
    set(OPENOCD_DEFAULT_PATH "${espressif_openocd_dir}/share/openocd/scripts" CACHE PATH "" FORCE)
  endif()
endif()

set(_esp32s3_bundle
  "${CMAKE_CURRENT_LIST_DIR}/mcumgr.conf"

  "${CMAKE_CURRENT_LIST_DIR}/programs/gpio.conf"
  "${CMAKE_CURRENT_LIST_DIR}/programs/thread_analyzer.conf"

  "${CMAKE_CURRENT_LIST_DIR}/debug.conf"
  "${CMAKE_CURRENT_LIST_DIR}/programs/stats.conf"
  "${CMAKE_CURRENT_LIST_DIR}/ram.conf"

  "${CMAKE_CURRENT_LIST_DIR}/filesystems/nvs.conf"
  "${CMAKE_CURRENT_LIST_DIR}/filesystems/img.conf"
  "${CMAKE_CURRENT_LIST_DIR}/filesystems/zvfs.conf"
  "${CMAKE_CURRENT_LIST_DIR}/filesystems/flash.conf"
  "${CMAKE_CURRENT_LIST_DIR}/programs/settings.conf"

  "${CMAKE_CURRENT_LIST_DIR}/networking/buf.conf"
  "${CMAKE_CURRENT_LIST_DIR}/networking/ipv4.conf"
  "${CMAKE_CURRENT_LIST_DIR}/networking/ipv6.conf"
  "${CMAKE_CURRENT_LIST_DIR}/networking/net.conf"
  "${CMAKE_CURRENT_LIST_DIR}/networking/sockets.conf"
  "${CMAKE_CURRENT_LIST_DIR}/networking/hostname.conf"
  "${CMAKE_CURRENT_LIST_DIR}/networking/statistics.conf"
  "${CMAKE_CURRENT_LIST_DIR}/networking/dns/server.conf"
  "${CMAKE_CURRENT_LIST_DIR}/networking/dns/resolver.conf"
  "${CMAKE_CURRENT_LIST_DIR}/networking/dhcpv4.conf"
  "${CMAKE_CURRENT_LIST_DIR}/networking/wifi.conf"
  "${CMAKE_CURRENT_LIST_DIR}/networking/sntp.conf"

  "${CMAKE_CURRENT_LIST_DIR}/services/mcumgr.conf"
)

if(BOARD MATCHES "^walter")
  set(firmware_EXTRA_CONF_FILE
    ${_esp32s3_bundle}
    "${CMAKE_CURRENT_LIST_DIR}/networking/pkt.conf"
    "${CMAKE_CURRENT_LIST_DIR}/networking/nat.conf"
    "${CMAKE_CURRENT_LIST_DIR}/networking/ppp.conf"
    "${CMAKE_CURRENT_LIST_DIR}/networking/modem.conf"
    "${CMAKE_CURRENT_LIST_DIR}/services/task_wdt.conf"
    CACHE INTERNAL ""
  )
  set(mcuboot_SNIPPET "espressif-flash-16M" CACHE INTERNAL "")
elseif(BOARD MATCHES "^xiao_esp32s3")
  set(_xiao_extra_conf
    ${_esp32s3_bundle}
    "${CMAKE_CURRENT_LIST_DIR}/networking/dns/mdns.conf"
  )
  if(BOARD_QUALIFIERS MATCHES "sense")
    list(APPEND _xiao_extra_conf
      "${CMAKE_CURRENT_LIST_DIR}/filesystems/fs.conf"
      "${CMAKE_CURRENT_LIST_DIR}/services/http/http.conf"
    )
  endif()
  set(firmware_EXTRA_CONF_FILE "${_xiao_extra_conf}" CACHE INTERNAL "")
  set(mcuboot_SNIPPET "espressif-flash-8M" CACHE INTERNAL "")
elseif(BOARD MATCHES "^esp32s3_devkitc")
  set(firmware_EXTRA_CONF_FILE
    ${_esp32s3_bundle}
    "${CMAKE_CURRENT_LIST_DIR}/networking/dns/mdns.conf"
    CACHE INTERNAL ""
  )
  set(mcuboot_SNIPPET "espressif-flash-8M" CACHE INTERNAL "")
endif()
