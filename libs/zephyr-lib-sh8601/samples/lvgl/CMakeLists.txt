# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

get_filename_component(SH8601_MODULE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../.. ABSOLUTE)
list(APPEND ZEPHYR_EXTRA_MODULES ${SH8601_MODULE_DIR})

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(lvgl)

FILE(GLOB app_sources src/*.c)
target_sources(app PRIVATE ${app_sources})
