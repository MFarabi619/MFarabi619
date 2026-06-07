cmake_minimum_required(VERSION 3.20.0)

if(DEFINED ENV{CONFIG_WIFI_CREDENTIALS_STATIC_SSID})
  file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/wifi_credentials.conf
       "CONFIG_WIFI_CREDENTIALS_STATIC=y\n"
       "CONFIG_WIFI_CREDENTIALS_STATIC_SSID=\"$ENV{CONFIG_WIFI_CREDENTIALS_STATIC_SSID}\"\n"
       "CONFIG_WIFI_CREDENTIALS_STATIC_PASSWORD=\"$ENV{CONFIG_WIFI_CREDENTIALS_STATIC_PASSWORD}\"\n")
  list(APPEND EXTRA_CONF_FILE ${CMAKE_CURRENT_BINARY_DIR}/wifi_credentials.conf)
endif()

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
  ${LIBS_FIRMWARE}/networking/dns/mdns.conf

  ${LIBS_FIRMWARE}/networking/wifi/default.conf
  ${LIBS_FIRMWARE}/networking/wifi/credentials.conf
  ${LIBS_FIRMWARE}/networking/wifi/esp.conf

  ${LIBS_FIRMWARE}/networking/wireguard.conf

  ${LIBS_FIRMWARE}/boards/xiao_esp32s3.conf
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

add_subdirectory(${LIBS_FIRMWARE} ${CMAKE_BINARY_DIR}/firmware-lib)
