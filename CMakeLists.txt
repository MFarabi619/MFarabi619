# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

if(DEFINED ENV{WIFI_SSID})
  set(wifi_conf "${CMAKE_CURRENT_BINARY_DIR}/wifi_credentials.conf")
  file(WRITE ${wifi_conf}
    "CONFIG_WIFI_CREDENTIALS_STATIC=y\n"
    "CONFIG_WIFI_CREDENTIALS_STATIC_SSID=\"$ENV{WIFI_SSID}\"\n"
    "CONFIG_WIFI_CREDENTIALS_STATIC_PASSWORD=\"$ENV{WIFI_PSK}\"\n"
  )
  list(APPEND EXTRA_CONF_FILE ${wifi_conf})
endif()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(microvisor)

rust_cargo_application(CRATE_NAME firmware FEATURES zephyr)

target_sources(app PRIVATE
  firmware/src/boot.c
  firmware/src/console/prompt.c
  firmware/src/console/fs_aliases.c
  firmware/src/services/provisioning_http.c
  firmware/src/services/sdcard.c
  firmware/src/services/filesystem_http.c
  firmware/src/services/http/api.c
  # firmware/src/services/websocket_shell.c
  # firmware/src/services/wifi_connectivity.c
  firmware/src/sensors/devices.c
  firmware/src/sensors/wind_speed.c
  firmware/src/sensors/wind_direction.c
  firmware/src/sensors/rainfall.c
  firmware/src/sensors/soil_moisture.c
)

target_include_directories(app PRIVATE include firmware/include)

zephyr_linker_sources(SECTIONS
  ${CMAKE_CURRENT_SOURCE_DIR}/firmware/linker/discard_defmt.ld
  ${CMAKE_CURRENT_SOURCE_DIR}/firmware/linker/http-resources.ld
)

zephyr_linker_section(NAME http_resource_desc_provisioning_service
                      KVMA RAM_REGION GROUP RODATA_REGION)
