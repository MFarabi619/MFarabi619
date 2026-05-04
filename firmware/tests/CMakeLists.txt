# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

set(APPLICATION_CONFIG_DIR ${CMAKE_CURRENT_SOURCE_DIR}/..)
set(KCONFIG_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../Kconfig)
list(APPEND EXTRA_CONF_FILE ${CMAKE_CURRENT_SOURCE_DIR}/prj.conf)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(unit_tests)

target_sources(app PRIVATE
  ../src/programs/led.c
  ../src/console/prompt.c
)

target_include_directories(app PRIVATE ../include)
