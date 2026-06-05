cmake_minimum_required(VERSION 3.20.0)

set(WORKSPACE_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)
set(WALTER_ROUTER_LIB ${WORKSPACE_ROOT}/libs/walter-router)
set(FIRMWARE_LIB ${WORKSPACE_ROOT}/libs/firmware)

list(APPEND EXTRA_CONF_FILE
  ${FIRMWARE_LIB}/rust.conf
  ${FIRMWARE_LIB}/boot/kernel.conf
  ${FIRMWARE_LIB}/boot/mcuboot.conf
  ${FIRMWARE_LIB}/boot/psram.conf
  ${FIRMWARE_LIB}/console/log.conf
  ${FIRMWARE_LIB}/console/shell.conf
  ${FIRMWARE_LIB}/console/debug.conf
  ${FIRMWARE_LIB}/filesystems/storage.conf
  ${FIRMWARE_LIB}/hardware/task_wdt.conf
  ${FIRMWARE_LIB}/networking/net.conf
  ${FIRMWARE_LIB}/networking/dns.conf
  ${FIRMWARE_LIB}/networking/wifi/wifi.conf
  ${FIRMWARE_LIB}/power/pm.conf
  ${FIRMWARE_LIB}/services/mcumgr.conf
  ${FIRMWARE_LIB}/boards/walter.conf
)

list(APPEND EXTRA_DTC_OVERLAY_FILE
  ${FIRMWARE_LIB}/boards/walter.overlay
)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(walter-router)

add_subdirectory(${WALTER_ROUTER_LIB} ${CMAKE_BINARY_DIR}/walter-router-lib)

if(CONFIG_WOLFSSH)
  zephyr_include_directories(${CMAKE_CURRENT_SOURCE_DIR})
endif()
