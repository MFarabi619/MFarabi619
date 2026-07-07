cmake_minimum_required(VERSION 3.20.0)

get_filename_component(SQLITE_MODULE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../.. ABSOLUTE)
get_filename_component(ZTEST_FANCY_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../zephyr-ztest-fancy ABSOLUTE)
list(APPEND ZEPHYR_EXTRA_MODULES ${SQLITE_MODULE_DIR} ${ZTEST_FANCY_DIR})

if(NOT BOARD)
  set(BOARD qemu_riscv32)
endif()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(sqlite_rust)
rust_cargo_application()
