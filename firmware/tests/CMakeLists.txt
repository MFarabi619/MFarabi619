# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

# Inherit the app's prj.conf and overlay
set(OVERLAY_CONFIG "${CMAKE_CURRENT_SOURCE_DIR}/../../prj.conf")
set(DTC_OVERLAY_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../../boards/esp32s3_devkitc_procpu.overlay")

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(unit_tests)

target_sources(app PRIVATE
  ../src/programs/led.c
  ../src/console/prompt.c
)

target_include_directories(app PRIVATE ../include)
