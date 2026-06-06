cmake_minimum_required(VERSION 3.20.0)

set(WORKSPACE_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)
set(LIBS_FIRMWARE ${WORKSPACE_ROOT}/libs/firmware)

list(APPEND SNIPPET espressif-flash-8M)

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

  ${LIBS_FIRMWARE}/networking/default.conf
  ${LIBS_FIRMWARE}/networking/hostname.conf
  ${LIBS_FIRMWARE}/networking/ipv4.conf
  ${LIBS_FIRMWARE}/networking/ipv6.conf
  ${LIBS_FIRMWARE}/networking/buf.conf
  ${LIBS_FIRMWARE}/networking/mgmt.conf
  ${LIBS_FIRMWARE}/networking/statistics.conf

  ${LIBS_FIRMWARE}/boards/xiao_esp32s3.conf

  ${CMAKE_CURRENT_SOURCE_DIR}/halow.conf
)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(halow_xiao)

rust_cargo_application(CRATE_NAME halow_xiao)
