cmake_minimum_required(VERSION 3.20.0)

# if(DEFINED ENV{OPENOCD})
#   set(OPENOCD "$ENV{OPENOCD}" CACHE STRING "" FORCE)
# endif()

set(LIBS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../libs)

set(LIBS_FIRMWARE           ${LIBS_DIR}/firmware)
set(LIBS_ZEPHYR_LIB_SQLITE  ${LIBS_DIR}/zephyr-lib-sqlite)
set(LIBS_ZEPHYR_ZTEST_FANCY ${LIBS_DIR}/zephyr-ztest-fancy)

list(APPEND EXTRA_ZEPHYR_MODULES
  ${LIBS_FIRMWARE}
  ${LIBS_ZEPHYR_LIB_SQLITE}
  ${LIBS_ZEPHYR_ZTEST_FANCY}
)

list(APPEND EXTRA_CONF_FILE
  \${ZEPHYR_FIRMWARE_MODULE_DIR}/rust.conf
  \${ZEPHYR_FIRMWARE_MODULE_DIR}/kernel.conf
  \${ZEPHYR_FIRMWARE_MODULE_DIR}/log.conf
  \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/shell.conf
)

if(NOT BOARD MATCHES "^qemu_")
  set(CONFIG_WIREGUARD_LOCAL_PRIVATE_KEY
      "$ENV{CONFIG_WIREGUARD_LOCAL_PRIVATE_KEY}" CACHE STRING "" FORCE)

  list(APPEND EXTRA_CONF_FILE
    ${CMAKE_CURRENT_SOURCE_DIR}/mcumgr.conf

    \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/thread_analyzer.conf

    \${ZEPHYR_FIRMWARE_MODULE_DIR}/debug.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/stats.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/ram.conf

    \${ZEPHYR_FIRMWARE_MODULE_DIR}/filesystems/nvs.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/filesystems/img.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/filesystems/zvfs.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/filesystems/flash.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/settings.conf

    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/buf.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/ipv4.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/ipv6.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/net.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/sockets.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/hostname.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/statistics.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/dns/server.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/dns/resolver.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/dhcpv4.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/wifi.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/networking/sntp.conf

    \${ZEPHYR_FIRMWARE_MODULE_DIR}/services/mcumgr.conf

    \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/hwinfo.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/gpio.conf
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

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(embedded)

rust_cargo_application(CRATE_NAME embedded)
