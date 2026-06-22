if("${ARCH}" STREQUAL "xtensa")
  include(${CMAKE_CURRENT_LIST_DIR}/zig-download.cmake)
  set(ZIG_EXECUTABLE "${ZIG_BIN}" CACHE FILEPATH "" FORCE)
else()
  find_program(ZIG_EXECUTABLE zig REQUIRED)
endif()
message(STATUS "zephyr-lang-zig: zig at ${ZIG_EXECUTABLE}")

function(add_zig_object zephyr_target zig_source)
  cmake_parse_arguments(ARG "" "DT" "" ${ARGN})

  set(_libc_txt "${CMAKE_CURRENT_BINARY_DIR}/zig_libc.txt")
  file(WRITE "${_libc_txt}"
    "include_dir=${SYSROOT_DIR}/include\n"
    "sys_include_dir=${SYSROOT_DIR}/include\n"
    "crt_dir=${SYSROOT_DIR}/lib\n"
    "msvc_lib_dir=\n"
    "kernel32_lib_dir=\n"
    "gcc_dir=\n"
  )

  get_filename_component(src_absolute "${zig_source}" ABSOLUTE)
  get_filename_component(src_name "${zig_source}" NAME_WE)
  set(_zig_prefix "${CMAKE_CURRENT_BINARY_DIR}/zig")
  set(_zig_cache "${CMAKE_CURRENT_BINARY_DIR}/.zig-cache")
  set(obj_path "${_zig_prefix}/obj/${src_name}.o")

  set(_dt_arg)
  if(ARG_DT)
    set(_dt_arg "-Ddt=${ARG_DT}")
  endif()

  # Resolve Zephyr's generator-expression include dirs/defs at build-generate
  # time, joined with '|' for build.zig to tokenize.
  add_custom_command(
    OUTPUT ${obj_path}
    COMMAND ${ZIG_EXECUTABLE} build
      --build-file ${ZIG_MODULE_DIR}/build.zig
      --cache-dir ${_zig_cache}
      --prefix ${_zig_prefix}
      -Dtarget=${ZIG_TARGET}
      -Dcpu=${ZIG_MCPU}
      -Doptimize=${CONFIG_ZIG_OPTIMIZE}
      -Droot=${src_absolute}
      -Doutput-name=${src_name}
      -Dticks-per-sec=${CONFIG_SYS_CLOCK_TICKS_PER_SEC}
      -Dlibc=${_libc_txt}
      "-Duser-includes=${SYSROOT_DIR}/include|$<JOIN:$<TARGET_PROPERTY:zephyr_interface,INTERFACE_INCLUDE_DIRECTORIES>,|>"
      "-Dsys-includes=$<JOIN:$<TARGET_PROPERTY:zephyr_interface,INTERFACE_SYSTEM_INCLUDE_DIRECTORIES>,|>"
      "-Dc-defines=$<JOIN:$<TARGET_PROPERTY:zephyr_interface,INTERFACE_COMPILE_DEFINITIONS>,|>"
      ${_dt_arg}
    DEPENDS ${src_absolute} ${_libc_txt} ${ARG_DT}
      ${ZIG_MODULE_DIR}/scripts/zephyr_stub.h
    VERBATIM
    COMMAND_EXPAND_LISTS
    COMMENT "zig build ${src_name} -> ${obj_path}"
  )

  target_sources(${zephyr_target} PRIVATE ${obj_path})
endfunction()
