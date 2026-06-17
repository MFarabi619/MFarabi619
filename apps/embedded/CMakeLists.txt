cmake_minimum_required(VERSION 3.20.0)

if(DEFINED ENV{OPENOCD})
  set(OPENOCD "$ENV{OPENOCD}" CACHE STRING "" FORCE)
endif()

set(LIBS_FIRMWARE ${CMAKE_CURRENT_SOURCE_DIR}/../../libs/firmware)

list(APPEND EXTRA_CONF_FILE
  ${LIBS_FIRMWARE}/rust.conf
  ${LIBS_FIRMWARE}/kernel.conf
  ${LIBS_FIRMWARE}/log.conf
  ${LIBS_FIRMWARE}/shell.conf

  ${CMAKE_CURRENT_SOURCE_DIR}/src/kernel.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/console/log.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/src/console/shell.conf
)

if(NOT BOARD MATCHES "^qemu_")
  file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/wireguard_credentials.conf
       "CONFIG_WIREGUARD_LOCAL_PRIVATE_KEY=\"$ENV{CONFIG_WIREGUARD_LOCAL_PRIVATE_KEY}\"\n")

  list(APPEND EXTRA_CONF_FILE
    ${CMAKE_CURRENT_BINARY_DIR}/wireguard_credentials.conf

    ${CMAKE_CURRENT_SOURCE_DIR}/src/programs/thread_analyzer.conf

    ${CMAKE_CURRENT_SOURCE_DIR}/src/esp32.conf

    ${CMAKE_CURRENT_SOURCE_DIR}/src/console/debug.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/console/stats.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/console/ram.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/console/mcumgr.conf

    ${CMAKE_CURRENT_SOURCE_DIR}/src/filesystems/nvs.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/filesystems/img.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/filesystems/zvfs.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/filesystems/flash.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/filesystems/settings.conf

    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/buf.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/ipv4.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/ipv6.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/net.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/sockets.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/hostname.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/statistics.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/dns/server.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/dns/resolver.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/dhcpv4.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/wifi.conf
    ${CMAKE_CURRENT_SOURCE_DIR}/src/networking/sntp.conf

    ${CMAKE_CURRENT_SOURCE_DIR}/src/services/mcumgr.conf

    ${CMAKE_CURRENT_SOURCE_DIR}/src/programs/hwinfo.conf
  )
endif()

if(BOARD MATCHES "^qemu_")
  list(APPEND EXTRA_CONF_FILE ${CMAKE_CURRENT_SOURCE_DIR}/src/filesystems/fs.conf)
endif()

if(BOARD MATCHES "^xiao_esp32s3")
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

rust_cargo_application(CRATE_NAME embedded)

target_sources_ifdef(CONFIG_NET_DHCPV4_SERVER app PRIVATE
  src/networking/dns/proxy.c
)

target_sources_ifdef(CONFIG_WIREGUARD app PRIVATE src/networking/wireguard/wireguard.c)
if(CONFIG_WIREGUARD)
  target_include_directories(app PRIVATE ${ZEPHYR_BASE}/subsys/net/lib/wireguard)
endif()

set_source_files_properties(
  src/networking/dns/proxy.c
  PROPERTIES INCLUDE_DIRECTORIES "${ZEPHYR_BASE}/subsys/net/lib/dns"
)

# NOTE: uncomment wolfssl/wolfssh projects in west.yml + add services/ssh/wolfssh.conf + ${LIBS_FIRMWARE}/posix.conf to app's EXTRA_CONF_FILE
# if(CONFIG_WOLFSSH)
#   zephyr_include_directories(${CMAKE_CURRENT_SOURCE_DIR}/src/services/ssh)
# endif()
