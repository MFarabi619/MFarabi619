cmake_minimum_required(VERSION 3.20.0)

if(DEFINED ENV{CONFIG_WIFI_CREDENTIALS_STATIC_SSID})
  file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/wifi_credentials.conf
       "CONFIG_WIFI_CREDENTIALS_STATIC=y\n"
       "CONFIG_WIFI_CREDENTIALS_STATIC_SSID=\"$ENV{CONFIG_WIFI_CREDENTIALS_STATIC_SSID}\"\n"
       "CONFIG_WIFI_CREDENTIALS_STATIC_PASSWORD=\"$ENV{CONFIG_WIFI_CREDENTIALS_STATIC_PASSWORD}\"\n")
  list(APPEND EXTRA_CONF_FILE ${CMAKE_CURRENT_BINARY_DIR}/wifi_credentials.conf)
endif()

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/wireguard_credentials.conf
     "CONFIG_WIREGUARD_LOCAL_PRIVATE_KEY=\"$ENV{CONFIG_WIREGUARD_LOCAL_PRIVATE_KEY}\"\n")
list(APPEND EXTRA_CONF_FILE ${CMAKE_CURRENT_BINARY_DIR}/wireguard_credentials.conf)

set(WORKSPACE_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)
set(LIBS_FIRMWARE ${WORKSPACE_ROOT}/libs/firmware)

list(APPEND SNIPPET espressif-flash-8M)

include(${LIBS_FIRMWARE}/default.cmake)

list(APPEND EXTRA_CONF_FILE
  ${LIBS_FIRMWARE}/networking/dns/mdns.conf
  ${LIBS_FIRMWARE}/networking/sntp.conf
  ${LIBS_FIRMWARE}/networking/dhcpv4.conf
  ${LIBS_FIRMWARE}/networking/wireguard.conf
  ${LIBS_FIRMWARE}/security/mbedtls.conf

  # NOTE: uncomment + add `-DDTC_OVERLAY_FILE=${LIBS_FIRMWARE}/networking/wifi/halow.overlay` to use
  # ${LIBS_FIRMWARE}/networking/wifi/halow.conf
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
project(embedded)

rust_cargo_application(CRATE_NAME embedded)

add_subdirectory(${LIBS_FIRMWARE} ${CMAKE_BINARY_DIR}/firmware-lib)
