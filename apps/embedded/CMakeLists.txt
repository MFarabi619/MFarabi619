cmake_minimum_required(VERSION 3.20.0)

if(DEFINED ENV{OPENOCD})
  set(OPENOCD "$ENV{OPENOCD}" CACHE STRING "" FORCE)
endif()

set(LIBS_FIRMWARE ${CMAKE_CURRENT_SOURCE_DIR}/../../libs/firmware)
set(LIBS_ZEPHYR_LIB_SQLITE ${CMAKE_CURRENT_SOURCE_DIR}/../../libs/zephyr-lib-sqlite)
set(LIBS_ZEPHYR_ZTEST_FANCY ${CMAKE_CURRENT_SOURCE_DIR}/../../libs/zephyr-ztest-fancy)
list(APPEND EXTRA_ZEPHYR_MODULES ${LIBS_FIRMWARE} ${LIBS_ZEPHYR_LIB_SQLITE} ${LIBS_ZEPHYR_ZTEST_FANCY})

list(APPEND EXTRA_CONF_FILE
  ${LIBS_FIRMWARE}/rust.conf
  ${LIBS_FIRMWARE}/kernel.conf
  ${LIBS_FIRMWARE}/log.conf
  ${LIBS_FIRMWARE}/programs/shell.conf
)

if(NOT BOARD MATCHES "^qemu_")
  file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/wireguard_credentials.conf
       "CONFIG_WIREGUARD_LOCAL_PRIVATE_KEY=\"$ENV{CONFIG_WIREGUARD_LOCAL_PRIVATE_KEY}\"\n")

  list(APPEND EXTRA_CONF_FILE
    ${CMAKE_CURRENT_BINARY_DIR}/wireguard_credentials.conf

    ${LIBS_FIRMWARE}/programs/thread_analyzer.conf

    ${LIBS_FIRMWARE}/esp32.conf

    ${LIBS_FIRMWARE}/debug.conf
    ${LIBS_FIRMWARE}/programs/stats.conf
    ${LIBS_FIRMWARE}/ram.conf

    ${LIBS_FIRMWARE}/filesystems/nvs.conf
    ${LIBS_FIRMWARE}/filesystems/img.conf
    ${LIBS_FIRMWARE}/filesystems/zvfs.conf
    ${LIBS_FIRMWARE}/filesystems/flash.conf
    ${LIBS_FIRMWARE}/programs/settings.conf

    ${LIBS_FIRMWARE}/networking/buf.conf
    ${LIBS_FIRMWARE}/networking/ipv4.conf
    ${LIBS_FIRMWARE}/networking/ipv6.conf
    ${LIBS_FIRMWARE}/networking/net.conf
    ${LIBS_FIRMWARE}/networking/sockets.conf
    ${LIBS_FIRMWARE}/networking/hostname.conf
    ${LIBS_FIRMWARE}/networking/statistics.conf
    ${LIBS_FIRMWARE}/networking/dns/server.conf
    ${LIBS_FIRMWARE}/networking/dns/resolver.conf
    ${LIBS_FIRMWARE}/networking/dhcpv4.conf
    ${LIBS_FIRMWARE}/networking/wifi.conf
    ${LIBS_FIRMWARE}/networking/sntp.conf

    ${LIBS_FIRMWARE}/services/mcumgr.conf

    ${LIBS_FIRMWARE}/programs/hwinfo.conf
    ${LIBS_FIRMWARE}/programs/gpio.conf
  )
endif()

if(BOARD MATCHES "^qemu_")
  list(APPEND EXTRA_CONF_FILE
    ${LIBS_FIRMWARE}/filesystems/fs.conf
    ${LIBS_ZEPHYR_LIB_SQLITE}/sqlite.conf
  )
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

if(BOARD STREQUAL "xiao_esp32s3" AND BOARD_QUALIFIERS MATCHES "/sense$")
  list(APPEND EXTRA_CONF_FILE
    ${LIBS_ZEPHYR_LIB_SQLITE}/sqlite.conf
  )
endif()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(embedded)

rust_cargo_application(CRATE_NAME embedded)
