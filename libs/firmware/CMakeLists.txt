cmake_minimum_required(VERSION 3.20.0)

list(APPEND EXTRA_CONF_FILE
  ${CMAKE_CURRENT_SOURCE_DIR}/rust.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/kernel.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/log.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/shell.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/posix.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/flash.conf
  ${CMAKE_CURRENT_SOURCE_DIR}/filesystem.conf
)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(firmware)

rust_cargo_application()
