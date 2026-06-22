if("${ARCH}" STREQUAL "xtensa")
  include(${CMAKE_CURRENT_LIST_DIR}/zig-download.cmake)
  set(ZIG_EXECUTABLE "${ZIG_BIN}" CACHE FILEPATH "" FORCE)
else()
  find_program(ZIG_EXECUTABLE zig REQUIRED)
endif()
message(STATUS "zephyr-lang-zig: zig at ${ZIG_EXECUTABLE}")

function(add_zig_object zephyr_target zig_source)
  cmake_parse_arguments(ARG "" "" "MODULES" ${ARGN})

  set(_libc_txt "${CMAKE_CURRENT_BINARY_DIR}/zig_libc.txt")
  file(WRITE "${_libc_txt}"
    "include_dir=${SYSROOT_DIR}/include\n"
    "sys_include_dir=${SYSROOT_DIR}/include\n"
    "crt_dir=${SYSROOT_DIR}/lib\n"
    "msvc_lib_dir=\n"
    "kernel32_lib_dir=\n"
    "gcc_dir=\n"
  )

  set(_build_config "${CMAKE_CURRENT_BINARY_DIR}/zig_build_config.zig")
  file(WRITE "${_build_config}"
    "pub const ticks_per_sec: i64 = ${CONFIG_SYS_CLOCK_TICKS_PER_SEC};\n"
  )

  zephyr_get_include_directories_for_lang(C _zephyr_includes)
  zephyr_get_compile_definitions_for_lang(C _zephyr_defines)

  get_filename_component(src_absolute "${zig_source}" ABSOLUTE)
  get_filename_component(src_name "${zig_source}" NAME)
  set(obj_path "${CMAKE_CURRENT_BINARY_DIR}/${src_name}.o")

  set(_user_mod_names)
  set(_user_mod_paths)
  foreach(_module ${ARG_MODULES})
    if(NOT _module MATCHES "^([^=]+)=(.+)$")
      message(FATAL_ERROR "add_zig_object: MODULES entry '${_module}' must be 'name=path'")
    endif()
    get_filename_component(_mod_path "${CMAKE_MATCH_2}" ABSOLUTE)
    list(APPEND _user_mod_names "${CMAKE_MATCH_1}")
    list(APPEND _user_mod_paths "${_mod_path}")
  endforeach()

  set(_root_dep_args --dep build_config)
  foreach(_n IN LISTS _user_mod_names)
    list(APPEND _root_dep_args --dep ${_n})
  endforeach()

  set(_per_module_args)
  list(LENGTH _user_mod_names _n_modules)
  set(_index 0)
  while(_index LESS _n_modules)
    list(GET _user_mod_names ${_index} _self_name)
    list(GET _user_mod_paths ${_index} _self_path)
    list(APPEND _per_module_args --dep build_config)
    foreach(_other IN LISTS _user_mod_names)
      if(NOT _other STREQUAL _self_name)
        list(APPEND _per_module_args --dep ${_other})
      endif()
    endforeach()
    list(APPEND _per_module_args -M${_self_name}=${_self_path})
    math(EXPR _index "${_index} + 1")
  endwhile()

  add_custom_command(
    OUTPUT ${obj_path}
    COMMAND ${ZIG_EXECUTABLE} build-obj
      -target ${ZIG_TARGET}
      -mcpu=${ZIG_MCPU}
      -O ${CONFIG_ZIG_OPTIMIZE}
      -fno-PIC -fno-PIE -fno-stack-check -freference-trace
      -femit-bin=${obj_path}
      --libc ${_libc_txt}
      ${_zephyr_includes}
      ${_zephyr_defines}
      ${_root_dep_args}
      -Mroot=${src_absolute}
      -Mbuild_config=${_build_config}
      ${_per_module_args}
    DEPENDS ${src_absolute} ${_build_config} ${_libc_txt} ${_user_mod_paths}
    COMMAND_EXPAND_LISTS
    VERBATIM
    COMMENT "zig build-obj ${src_name} -> ${obj_path}"
  )

  target_sources(${zephyr_target} PRIVATE ${obj_path})
endfunction()
