cmake_minimum_required(VERSION 3.20.0)

list(APPEND ZEPHYR_EXTRA_MODULES ${CMAKE_CURRENT_SOURCE_DIR}/../..)

if(NOT BOARD)
  set(BOARD qemu_riscv32)
endif()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(zig_clay_tui LANGUAGES C)

zig_sample_app(BUILD_FILE ${CMAKE_CURRENT_SOURCE_DIR}/build.zig)
