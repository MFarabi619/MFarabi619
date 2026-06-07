cmake_minimum_required(VERSION 3.20.0)

set(WORKSPACE_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)
set(LIBS_FIRMWARE ${WORKSPACE_ROOT}/libs/firmware)

list(APPEND EXTRA_CONF_FILE
  ${LIBS_FIRMWARE}/rust.conf

  ${LIBS_FIRMWARE}/boot/kernel.conf
  ${LIBS_FIRMWARE}/boot/mcuboot.conf
  ${LIBS_FIRMWARE}/boot/thread_analyzer.conf

  ${LIBS_FIRMWARE}/hardware/esp_spiram.conf

  ${LIBS_FIRMWARE}/console/logger.conf
  ${LIBS_FIRMWARE}/console/shell.conf
  ${LIBS_FIRMWARE}/console/debug.conf
  ${LIBS_FIRMWARE}/console/statistics.conf

  ${LIBS_FIRMWARE}/filesystems/zvfs.conf
  ${LIBS_FIRMWARE}/filesystems/flash.conf
  ${LIBS_FIRMWARE}/filesystems/nvs.conf
  ${LIBS_FIRMWARE}/filesystems/settings.conf
  ${LIBS_FIRMWARE}/filesystems/img.conf

  ${LIBS_FIRMWARE}/networking/default.conf
  ${LIBS_FIRMWARE}/networking/sockets.conf
  ${LIBS_FIRMWARE}/networking/hostname.conf
  ${LIBS_FIRMWARE}/networking/ipv4.conf
  ${LIBS_FIRMWARE}/networking/ipv6.conf
  ${LIBS_FIRMWARE}/networking/buf.conf
  ${LIBS_FIRMWARE}/networking/mgmt.conf
  ${LIBS_FIRMWARE}/networking/statistics.conf
  ${LIBS_FIRMWARE}/networking/dns/resolver.conf
  ${LIBS_FIRMWARE}/networking/dns/server.conf
  ${LIBS_FIRMWARE}/networking/dhcpv4.conf
  ${LIBS_FIRMWARE}/networking/pkt.conf
  ${LIBS_FIRMWARE}/networking/ppp.conf

  ${LIBS_FIRMWARE}/networking/wifi/default.conf
  ${LIBS_FIRMWARE}/networking/wifi/credentials.conf
  ${LIBS_FIRMWARE}/networking/wifi/esp.conf

  ${LIBS_FIRMWARE}/networking/modem.conf
  ${LIBS_FIRMWARE}/networking/cellular/default.conf

  ${LIBS_FIRMWARE}/power/pm.conf
  ${LIBS_FIRMWARE}/services/mcumgr.conf
  ${LIBS_FIRMWARE}/services/task_wdt.conf

  ${LIBS_FIRMWARE}/boards/walter.conf
)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(walter-router)

rust_cargo_application(CRATE_NAME walter_router)

add_subdirectory(${LIBS_FIRMWARE} ${CMAKE_BINARY_DIR}/firmware-lib)

if(CONFIG_WOLFSSH)
  zephyr_include_directories(${CMAKE_CURRENT_SOURCE_DIR})
endif()
