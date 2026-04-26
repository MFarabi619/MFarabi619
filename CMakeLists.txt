# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(microvisor)

rust_cargo_application(CRATE_NAME firmware FEATURES zephyr)

target_sources(app PRIVATE
  firmware/src/main.c
  firmware/src/console/prompt.c
  firmware/src/console/fs_aliases.c
  firmware/src/services/provisioning_http.c
)

target_include_directories(app PRIVATE include firmware/include)

zephyr_linker_sources(SECTIONS
  ${CMAKE_CURRENT_SOURCE_DIR}/firmware/linker/discard_defmt.ld
  ${CMAKE_CURRENT_SOURCE_DIR}/firmware/linker/http-resources.ld
)
