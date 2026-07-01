cmake_minimum_required(VERSION 3.20.0)

set(LIBS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../libs)

list(APPEND EXTRA_ZEPHYR_MODULES
  ${CMAKE_CURRENT_LIST_DIR}
  ${LIBS_DIR}/zephyr-lib-sqlite
  ${LIBS_DIR}/zephyr-lib-oh-my-zephyr
  ${LIBS_DIR}/zephyr-ztest-fancy
)

set(BOARD_FLASH_RUNNER probe-rs)

macro(app_set_runner_args)
  get_property(_app_runner_args_queued GLOBAL PROPERTY _APP_RUNNER_ARGS_QUEUED SET)
  if(NOT _app_runner_args_queued)
    set_property(GLOBAL PROPERTY _APP_RUNNER_ARGS_QUEUED 1)

    if(BOARD MATCHES "^esp32s3_devkitc")
      board_runner_args(probe-rs "--dev-id=303a:1001:DC:B4:D9:0C:5E:F8")
    elseif(BOARD MATCHES "^xiao_esp32s3" AND BOARD_QUALIFIERS MATCHES "sense")
      board_runner_args(probe-rs "--dev-id=303a:1001:CC:BA:97:16:2B:68")
    elseif(BOARD MATCHES "^xiao_esp32s3")
      board_runner_args(probe-rs "--dev-id=303a:1001:D8:3B:DA:74:82:E8")
    elseif(BOARD MATCHES "^walter")
      board_runner_args(probe-rs "--dev-id=303a:1001:D0:CF:13:54:27:18")
    elseif(BOARD MATCHES "^esp32_devkitc")
      board_runner_args(probe-rs "--dev-id=1A86:7523")
    elseif(BOARD MATCHES "^stm32f3_disco")
      board_runner_args(probe-rs "--protocol=swd" "--dev-id=0483:374b:066FFF494877514867152643")
    elseif(BOARD MATCHES "^nucleo_h723zg")
      board_runner_args(probe-rs "--chip=stm32h723zg" "--protocol=swd" "--dev-id=0483:374e:003E00203234510237333934")
    endif()

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
