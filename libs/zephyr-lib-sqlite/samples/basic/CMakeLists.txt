cmake_minimum_required(VERSION 3.20.0)

get_filename_component(SQLITE_MODULE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../.. ABSOLUTE)
list(APPEND ZEPHYR_EXTRA_MODULES ${SQLITE_MODULE_DIR})

if(NOT BOARD)
  set(BOARD qemu_riscv32)
endif()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(sqlite_basic LANGUAGES C)

target_sources(app PRIVATE
  src/main.c
  src/sqlite_shell.c
)
