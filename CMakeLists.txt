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

set(LIBS_FIRMWARE ${CMAKE_CURRENT_SOURCE_DIR}/libs/firmware)

set(APPLICATION_CONFIG_DIR ${CMAKE_CURRENT_SOURCE_DIR}/apps/embedded)
set(KCONFIG_ROOT           ${CMAKE_CURRENT_SOURCE_DIR}/apps/embedded/Kconfig)

include(${LIBS_FIRMWARE}/default.cmake)

# BOARD is set by Zephyr's CMake init during find_package(Zephyr); but EXTRA_CONF_FILE
# must be populated before that. Under sysbuild the value lives in SYSBUILD_CACHE so
# we pre-read it to drive the role conditional below.
if(DEFINED SYSBUILD_CACHE AND EXISTS ${SYSBUILD_CACHE})
  file(STRINGS ${SYSBUILD_CACHE} _sysbuild_board_line REGEX "^BOARD:STRING=")
  if(_sysbuild_board_line)
    string(REGEX REPLACE "^BOARD:STRING=" "" BOARD "${_sysbuild_board_line}")
  endif()
endif()

if(BOARD MATCHES "^walter")
  # Router role: upstream cellular + downstream WiFi-AP + NAT + DNS
  list(APPEND EXTRA_CONF_FILE
    ${LIBS_FIRMWARE}/networking/pkt.conf
    ${LIBS_FIRMWARE}/networking/ppp.conf

    ${LIBS_FIRMWARE}/networking/modem.conf
    ${LIBS_FIRMWARE}/networking/cellular/default.conf

    ${LIBS_FIRMWARE}/hardware/regulator.conf

    ${LIBS_FIRMWARE}/power/pm.conf
    ${LIBS_FIRMWARE}/services/task_wdt.conf
  )
elseif(BOARD MATCHES "^xiao_esp32s3")
  # Node role: WiFi STA + WireGuard underlay + AP fallback for provisioning
  list(APPEND SNIPPET espressif-flash-8M)

  list(APPEND EXTRA_CONF_FILE
    ${LIBS_FIRMWARE}/networking/dns/mdns.conf
    # NOTE: wireguard.conf temporarily out — vendor wg.c + wg_shell.c have
    # unconditional sockaddr_in6 memcpys that trigger -Warray-bounds when
    # CONFIG_NET_IPV6=n. Re-enable once we patch vendor to cfg-gate the
    # IPv6 paths (or upstream picks it up).
    # ${LIBS_FIRMWARE}/networking/wireguard.conf
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
endif()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(embedded)

add_subdirectory(apps/embedded)

add_subdirectory(${LIBS_FIRMWARE} ${CMAKE_BINARY_DIR}/firmware-lib)
