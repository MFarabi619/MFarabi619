cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(firmware_renode_scd41)

target_sources(app PRIVATE
  src/scd41_test.c
  ../../src/sensors/devices.c
)
