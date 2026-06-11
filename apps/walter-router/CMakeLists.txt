cmake_minimum_required(VERSION 3.20.0)

set(WORKSPACE_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)
set(LIBS_FIRMWARE ${WORKSPACE_ROOT}/libs/firmware)

include(${LIBS_FIRMWARE}/default.cmake)

list(APPEND EXTRA_CONF_FILE
  ${LIBS_FIRMWARE}/networking/dhcpv4.conf
  ${LIBS_FIRMWARE}/networking/pkt.conf
  ${LIBS_FIRMWARE}/networking/ppp.conf

  ${LIBS_FIRMWARE}/networking/modem.conf
  ${LIBS_FIRMWARE}/networking/cellular/default.conf

  ${LIBS_FIRMWARE}/hardware/regulator.conf

  ${LIBS_FIRMWARE}/power/pm.conf
  ${LIBS_FIRMWARE}/services/task_wdt.conf
)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(walter-router)

rust_cargo_application(CRATE_NAME walter_router)

add_subdirectory(${LIBS_FIRMWARE} ${CMAKE_BINARY_DIR}/firmware-lib)
