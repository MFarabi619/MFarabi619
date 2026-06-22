cmake_minimum_required(VERSION 3.20.0)

set(LIBS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../libs)

list(APPEND EXTRA_ZEPHYR_MODULES
  ${CMAKE_CURRENT_LIST_DIR}
  ${LIBS_DIR}/zephyr-lib-sqlite
  ${LIBS_DIR}/zephyr-ztest-fancy
)

list(APPEND EXTRA_CONF_FILE
  ${CMAKE_CURRENT_LIST_DIR}/rust.conf
  ${CMAKE_CURRENT_LIST_DIR}/kernel.conf
  ${CMAKE_CURRENT_LIST_DIR}/log.conf
  ${CMAKE_CURRENT_LIST_DIR}/rtt.conf
  ${CMAKE_CURRENT_LIST_DIR}/programs/shell.conf
  ${CMAKE_CURRENT_LIST_DIR}/programs/hwinfo.conf
)

if(BOARD MATCHES "^stm32f3_disco")
  list(APPEND EXTRA_CONF_FILE
    ${CMAKE_CURRENT_LIST_DIR}/programs/gpio.conf
    ${CMAKE_CURRENT_LIST_DIR}/programs/i2c.conf
    ${CMAKE_CURRENT_LIST_DIR}/programs/input.conf
    ${CMAKE_CURRENT_LIST_DIR}/programs/led.conf
    ${CMAKE_CURRENT_LIST_DIR}/programs/sensor.conf
  )
endif()

function(app_set_runner_args)
  get_property(_done GLOBAL PROPERTY APP_RUNNER_ARGS_DONE)
  if(_done)
    return()
  endif()
  set_property(GLOBAL PROPERTY APP_RUNNER_ARGS_DONE TRUE)

  if(BOARD MATCHES "^esp32s3_devkitc")
    board_runner_args(probe-rs
      "-O=--preset=esp32s3_devkitc"
      "--gdb-init-file=${APPLICATION_SOURCE_DIR}/.gdbinit"
    )
  endif()

  if(BOARD MATCHES "^walter")
    set(_esp_device "hwgrep://D0:CF:13:54:27:18")
  elseif(BOARD MATCHES "^xiao_esp32s3" AND BOARD_QUALIFIERS MATCHES "sense")
    set(_esp_device "hwgrep://CC:BA:97:16:2B:68")
  elseif(BOARD MATCHES "^esp32s3_devkitc")
    set(_esp_device "hwgrep://DC:B4:D9:0C:5E:F8")
  endif()
  if(_esp_device)
    board_runner_args(esp32 "--esp-device=${_esp_device}")
  endif()
endfunction()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(firmware)

if(BOARD MATCHES "^esp32s3_devkitc")
  set_property(TARGET runners_yaml_props_target APPEND_STRING
    PROPERTY yaml_contents "flash-runner: probe-rs\n")
endif()

if(CONFIG_FILE_SYSTEM AND CONFIG_ZTEST_FANCY)
  target_sources(app PRIVATE filesystems/tests.c)
endif()

if(CONFIG_SHELL_ALIASES_HAS_FILE)
  generate_shell_aliases_inc_file_for_target(
    app
    ${CMAKE_CURRENT_LIST_DIR}/programs/shell.aliases.txt
    ${ZEPHYR_BINARY_DIR}/include/generated/generated-shell-aliases.inc
  )
endif()

target_sources_ifdef(CONFIG_NET_DHCPV4_SERVER app PRIVATE networking/dns/proxy.c)
if(CONFIG_NET_DHCPV4_SERVER)
  set_source_files_properties(networking/dns/proxy.c
    PROPERTIES INCLUDE_DIRECTORIES "${ZEPHYR_BASE}/subsys/net/lib/dns")
endif()

target_sources_ifdef(CONFIG_WIREGUARD app PRIVATE networking/wireguard/wireguard.c)
target_include_directories_ifdef(CONFIG_WIREGUARD app PRIVATE "${ZEPHYR_BASE}/subsys/net/lib/wireguard")

target_sources_ifdef(CONFIG_HTTP_SERVER app PRIVATE services/http/http.c)
zephyr_linker_sources_ifdef(CONFIG_HTTP_SERVER SECTIONS services/http/http_sections.ld)

rust_cargo_application(CRATE_NAME firmware)
