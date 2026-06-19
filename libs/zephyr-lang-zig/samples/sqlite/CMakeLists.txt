cmake_minimum_required(VERSION 3.20.0)

list(APPEND ZEPHYR_EXTRA_MODULES
  ${CMAKE_CURRENT_SOURCE_DIR}/../..
  ${CMAKE_CURRENT_SOURCE_DIR}/../../../zephyr-lib-sqlite
)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(zig_sqlite LANGUAGES C)

zig_sample_app()
