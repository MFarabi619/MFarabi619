cmake_minimum_required(VERSION 3.20.0)

if(DEFINED ENV{CONFIG_WIFI_CREDENTIALS_STATIC_SSID})
  file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/wifi_credentials.conf
       "CONFIG_WIFI_CREDENTIALS_STATIC=y\n"
       "CONFIG_WIFI_CREDENTIALS_STATIC_SSID=\"$ENV{CONFIG_WIFI_CREDENTIALS_STATIC_SSID}\"\n"
       "CONFIG_WIFI_CREDENTIALS_STATIC_PASSWORD=\"$ENV{CONFIG_WIFI_CREDENTIALS_STATIC_PASSWORD}\"\n")
  list(APPEND EXTRA_CONF_FILE ${CMAKE_CURRENT_BINARY_DIR}/wifi_credentials.conf)
endif()

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
  ${FIRMWARE_LIB}/filesystems/storage.conf
  ${FIRMWARE_LIB}/networking/net.conf
  ${FIRMWARE_LIB}/networking/dns.conf
  ${FIRMWARE_LIB}/networking/wifi/wifi.conf
  ${FIRMWARE_LIB}/boards/xiao_esp32s3.conf
)

function(app_set_runner_args)
  board_runner_args(probe-rs
    "--chip" "esp32s3"
    "--protocol" "jtag"
    "--file-type" "bin"
    "--base-address=0x20000"
  )
endfunction()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(xiao)

rust_cargo_application(CRATE_NAME xiao)

add_subdirectory(${FIRMWARE_LIB} ${CMAKE_BINARY_DIR}/firmware-lib)
