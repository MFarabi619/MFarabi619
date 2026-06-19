cmake_minimum_required(VERSION 3.20.0)

list(APPEND ZEPHYR_EXTRA_MODULES ${CMAKE_CURRENT_SOURCE_DIR}/../..)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(zig_sqlite LANGUAGES C)

# Reference the same SQLite C source the Rust firmware uses — single source of
# truth for the amalgamation, VFS, and config. If/when this grows into its own
# Zephyr module (libs/embedded-sqlite was the earlier shape) the path moves
# but the sample shouldn't need to change much.
set(SQLITE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../firmware/programs/sqlite)

target_sources(app PRIVATE
  ${SQLITE_DIR}/sqlite3.c
  ${SQLITE_DIR}/vfs.c
  ${SQLITE_DIR}/init.c
)

target_include_directories(app PRIVATE ${SQLITE_DIR})

# Amalgamation is generated upstream code; its warnings are intentional and
# tracked at sqlite.org. Local fixes would be lost on every bump.
set_source_files_properties(
  ${SQLITE_DIR}/sqlite3.c
  PROPERTIES COMPILE_FLAGS "-w -DSQLITE_CUSTOM_INCLUDE=sqlite_config.h"
)

zig_sample_app()
