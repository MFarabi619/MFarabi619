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

set(KCONFIG_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/Kconfig)

if(DEFINED ENV{OPENOCD})
  set(OPENOCD "$ENV{OPENOCD}" CACHE STRING "" FORCE)
endif()

list(APPEND EXTRA_CONF_FILE
  ${CMAKE_CURRENT_SOURCE_DIR}/rust.conf

  ${CMAKE_CURRENT_SOURCE_DIR}/src/boot/kernel.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/boot/thread_analyzer.conf

  ${CMAKE_CURRENT_SOURCE_DIR}/src/hardware/esp_spiram.conf

  ${CMAKE_CURRENT_SOURCE_DIR}/src/console/log.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/console/shell.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/console/debug.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/console/stats.conf

  ${CMAKE_CURRENT_SOURCE_DIR}/src/filesystems/nvs.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/filesystems/img.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/filesystems/zvfs.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/filesystems/flash.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/filesystems/settings.conf

  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/buf.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/ipv4.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/ipv6.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/mgmt.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/default.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/sockets.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/hostname.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/statistics.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/dns/server.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/dns/resolver.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/dhcpv4.conf

  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/wifi/esp32.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/wifi/default.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/wifi/credentials.conf

  ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/sntp.conf

  ${CMAKE_CURRENT_SOURCE_DIR}/src/services/mcumgr.conf

  ${CMAKE_CURRENT_SOURCE_DIR}/src/programs/hwinfo.conf
)

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
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/pkt.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/ppp.conf

    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/modem.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/cellular/default.conf

    ${CMAKE_CURRENT_SOURCE_DIR}/src/hardware/regulator.conf

    ${CMAKE_CURRENT_SOURCE_DIR}/src/power/pm.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/services/task_wdt.conf
  )
elseif(BOARD MATCHES "^xiao_esp32s3")
  # Node role: WiFi STA + WireGuard underlay + AP fallback for provisioning
  list(APPEND SNIPPET espressif-flash-8M)

  list(APPEND EXTRA_CONF_FILE
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/dns/mdns.conf
    # NOTE: wireguard.conf temporarily out — vendor wg.c + wg_shell.c have
    # unconditional sockaddr_in6 memcpys that trigger -Warray-bounds when
    # CONFIG_NET_IPV6=n. Re-enable once we patch vendor to cfg-gate the
    # IPv6 paths (or upstream picks it up).
    # ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/wireguard.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/security/mbedtls.conf

    # NOTE: uncomment + add `-DDTC_OVERLAY_FILE=${CMAKE_CURRENT_SOURCE_DIR}/src/networking/wifi/halow.overlay` to use
    # ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/wifi/halow.conf
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
project(firmware)

rust_cargo_application(CRATE_NAME firmware)

target_sources(app PRIVATE src/networking/wifi/wifi.c)

target_include_directories(app PRIVATE ${ZEPHYR_BASE}/subsys/net/ip)

target_sources_ifdef(CONFIG_NET_PKT_FILTER_IPV4_HOOK app PRIVATE
  src/networking/nat/nat.c
  src/networking/nat/conntrack.c
)

target_sources_ifdef(CONFIG_NET_DHCPV4_SERVER app PRIVATE
  src/networking/dns/proxy.c
)

target_sources_ifdef(CONFIG_MODEM_CELLULAR app PRIVATE src/networking/cellular/cellular.c)

target_sources_ifdef(CONFIG_WIREGUARD app PRIVATE src/networking/wireguard/wireguard.c)
if(CONFIG_WIREGUARD)
  target_include_directories(app PRIVATE ${ZEPHYR_BASE}/subsys/net/lib/wireguard)
endif()

set_source_files_properties(
  src/networking/dns/proxy.c
  PROPERTIES INCLUDE_DIRECTORIES "${ZEPHYR_BASE}/subsys/net/lib/dns"
)

# NOTE: uncomment wolfssl/wolfssh projects in west.yml + add src/services/ssh/wolfssh.conf + src/boot/posix.conf to app's EXTRA_CONF_FILE
# if(CONFIG_WOLFSSH)
#   zephyr_include_directories(${CMAKE_CURRENT_SOURCE_DIR}/src/services/ssh)
# endif()
