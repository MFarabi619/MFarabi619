cmake_minimum_required(VERSION 3.20.0)

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

if(BOARD MATCHES "^stm32f3_disco")
  list(APPEND EXTRA_CONF_FILE
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/gpio.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/hwinfo.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/i2c.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/input.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/led.conf
    \${ZEPHYR_FIRMWARE_MODULE_DIR}/programs/sensor.conf
  )
endif()

function(app_set_runner_args)
  if(BOARD MATCHES "^xiao_esp32s3")
    board_runner_args(probe-rs
      "--chip" "esp32s3"
      "--protocol" "jtag"
      "--file-type" "bin"
      "--base-address=0x20000"
    )
  endif()
endfunction()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(embedded)

rust_cargo_application(CRATE_NAME embedded)
