cmake_minimum_required(VERSION 3.20.0)

set(LIBS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../libs)

list(APPEND EXTRA_ZEPHYR_MODULES
  ${CMAKE_CURRENT_LIST_DIR}
  ${LIBS_DIR}/zephyr-lib-sqlite
  ${LIBS_DIR}/zephyr-lib-oh-my-zephyr
  ${LIBS_DIR}/zephyr-ztest-fancy
)

list(APPEND EXTRA_CONF_FILE
  ${CMAKE_CURRENT_LIST_DIR}/rust.conf
  ${CMAKE_CURRENT_LIST_DIR}/kernel.conf
  ${CMAKE_CURRENT_LIST_DIR}/log.conf
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

set(BOARD_FLASH_RUNNER probe-rs)

macro(app_set_runner_args)
  get_property(_probe_rs_queued GLOBAL PROPERTY _PROBE_RS_PRESET_QUEUED SET)
  if(NOT _probe_rs_queued)
    set_property(GLOBAL PROPERTY _PROBE_RS_PRESET_QUEUED 1)
    string(REGEX REPLACE "/" "_" _preset "${BOARD}/${BOARD_QUALIFIERS}")
    board_runner_args(probe-rs "-O=--preset=${_preset}")

    get_property(_probe_rs_args GLOBAL PROPERTY BOARD_RUNNER_ARGS_EXPLICIT_probe_rs)
    set(_chip "")
    set(_prev_was_chip 0)
    foreach(_arg ${_probe_rs_args})
      if(_prev_was_chip)
        set(_chip "${_arg}")
        set(_prev_was_chip 0)
      elseif(_arg MATCHES "^--chip=(.+)$")
        set(_chip "${CMAKE_MATCH_1}")
      elseif(_arg STREQUAL "--chip")
        set(_prev_was_chip 1)
      endif()
    endforeach()
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/rust)
    if(_chip)
      file(WRITE ${CMAKE_BINARY_DIR}/rust/probe_rs_meta.rs
"probe_rs_meta::chip!(b\"${_chip}\");
probe_rs_meta::timeout!(60);
")
    else()
      file(WRITE ${CMAKE_BINARY_DIR}/rust/probe_rs_meta.rs "")
      message(STATUS "No --chip= in probe-rs runner args for ${BOARD}; probe-rs-meta omitted")
    endif()

    file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/.gdbinit [[
set print asm-demangle on
set print pretty on
set style sources on
set confirm off
break rust_main
continue
step
]])
    board_runner_args(probe-rs "--gdb-init-file=${CMAKE_CURRENT_BINARY_DIR}/.gdbinit")

    board_runner_args(openocd "--cmd-pre-init=adapter speed 950")
    board_runner_args(openocd "--gdb-init=source ${CMAKE_CURRENT_BINARY_DIR}/.gdbinit")
    foreach(_cmd
      "monitor stm32f3x.tpiu configure -protocol uart -traceclk 72000000 -pin-freq 2000000 -formatter 0 -output ${CMAKE_CURRENT_BINARY_DIR}/itm.txt"
      "monitor stm32f3x.tpiu enable"
      "monitor itm port 0 on")
      board_runner_args(openocd "--gdb-init=${_cmd}")
    endforeach()
  endif()
endmacro()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(firmware)

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/discard-rust-gnu-stack.ld
  "/DISCARD/ : { *(.note.GNU-stack) }\n")
zephyr_linker_sources(SECTIONS ${CMAKE_CURRENT_BINARY_DIR}/discard-rust-gnu-stack.ld)
zephyr_linker_sources(SECTIONS ${CMAKE_CURRENT_LIST_DIR}/probe-rs-meta.ld)

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
