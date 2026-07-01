if(NOT BOARD)
  set(BOARD qemu_riscv32)
endif()

if(BOARD MATCHES "^esp32s3" OR BOARD MATCHES "^xiao_esp32s3" OR BOARD MATCHES "^walter")
  file(GLOB espressif_openocd_installs LIST_DIRECTORIES true
    "$ENV{HOME}/.espressif/tools/openocd-esp32/*/openocd-esp32")
  if(espressif_openocd_installs)
    list(GET espressif_openocd_installs 0 espressif_openocd_dir)
    get_filename_component(espressif_toolchain_root "${espressif_openocd_dir}" DIRECTORY)
    set(ESPRESSIF_TOOLCHAIN_PATH "${espressif_toolchain_root}" CACHE PATH "" FORCE)
    set(OPENOCD "${espressif_openocd_dir}/bin/openocd" CACHE FILEPATH "" FORCE)
    set(OPENOCD_DEFAULT_PATH "${espressif_openocd_dir}/share/openocd/scripts" CACHE PATH "" FORCE)
  endif()
endif()

if(BOARD_QUALIFIERS MATCHES "esp32s3")
  set(firmware_EXTRA_CONF_FILE "${CMAKE_CURRENT_LIST_DIR}/esp32s3-base.conf" CACHE INTERNAL "")
endif()

