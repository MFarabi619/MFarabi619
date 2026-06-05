cmake_minimum_required(VERSION 3.20.0)

set(WORKSPACE_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)
set(FIRMWARE_LIB ${WORKSPACE_ROOT}/libs/firmware)

list(APPEND SNIPPET espressif-flash-8M)

list(APPEND EXTRA_CONF_FILE
  ${FIRMWARE_LIB}/rust.conf
  ${FIRMWARE_LIB}/boot/kernel.conf
  ${FIRMWARE_LIB}/boot/mcuboot.conf
  ${FIRMWARE_LIB}/boot/psram.conf
  ${FIRMWARE_LIB}/console/log.conf
  ${FIRMWARE_LIB}/console/shell.conf
  ${FIRMWARE_LIB}/console/debug.conf
  ${FIRMWARE_LIB}/networking/net.conf
  ${FIRMWARE_LIB}/networking/wifi/halow/halow.conf
  ${FIRMWARE_LIB}/boards/xiao_esp32s3.conf
)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(halow_xiao)

rust_cargo_application(CRATE_NAME halow_xiao)
