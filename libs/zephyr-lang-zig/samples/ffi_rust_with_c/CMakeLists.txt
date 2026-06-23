cmake_minimum_required(VERSION 3.20.0)

list(APPEND ZEPHYR_EXTRA_MODULES ${CMAKE_CURRENT_SOURCE_DIR}/../..)

if(NOT BOARD)
  set(BOARD qemu_riscv32)
endif()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(zig_ffi_rust_with_c LANGUAGES C)

set(_rust_lib ${CMAKE_CURRENT_BINARY_DIR}/zig/lib/librust_ffi.a)
zig_sample_app(
  BUILD_FILE ${CMAKE_CURRENT_SOURCE_DIR}/build.zig
  EXTRA_OUTPUTS ${_rust_lib}
)
target_include_directories(app PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_sources(app PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src/c_sum16.c)
target_link_libraries(app PRIVATE ${_rust_lib})
