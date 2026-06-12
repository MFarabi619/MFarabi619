if(DEFINED ENV{OPENOCD})
  set(OPENOCD "$ENV{OPENOCD}" CACHE STRING "" FORCE)
endif()

list(APPEND EXTRA_CONF_FILE
  ${CMAKE_CURRENT_LIST_DIR}/rust.conf

  ${CMAKE_CURRENT_LIST_DIR}/boot/kernel.conf
  ${CMAKE_CURRENT_LIST_DIR}/boot/thread_analyzer.conf

  ${CMAKE_CURRENT_LIST_DIR}/hardware/esp_spiram.conf

  ${CMAKE_CURRENT_LIST_DIR}/console/log.conf
  ${CMAKE_CURRENT_LIST_DIR}/console/shell.conf
  ${CMAKE_CURRENT_LIST_DIR}/console/debug.conf
  ${CMAKE_CURRENT_LIST_DIR}/console/stats.conf

  ${CMAKE_CURRENT_LIST_DIR}/filesystems/nvs.conf
  ${CMAKE_CURRENT_LIST_DIR}/filesystems/img.conf
  ${CMAKE_CURRENT_LIST_DIR}/filesystems/zvfs.conf
  ${CMAKE_CURRENT_LIST_DIR}/filesystems/flash.conf
  ${CMAKE_CURRENT_LIST_DIR}/filesystems/settings.conf

  ${CMAKE_CURRENT_LIST_DIR}/networking/buf.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/ipv4.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/ipv6.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/mgmt.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/default.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/sockets.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/hostname.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/statistics.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/dns/server.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/dns/resolver.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/dhcpv4.conf

  ${CMAKE_CURRENT_LIST_DIR}/networking/wifi/esp32.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/wifi/default.conf
  ${CMAKE_CURRENT_LIST_DIR}/networking/wifi/credentials.conf

  ${CMAKE_CURRENT_LIST_DIR}/networking/sntp.conf

  ${CMAKE_CURRENT_LIST_DIR}/services/mcumgr.conf

  ${CMAKE_CURRENT_LIST_DIR}/programs/hwinfo.conf
)
