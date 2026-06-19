find_program(ZIG_EXECUTABLE zig REQUIRED)
message(STATUS "zephyr-lang-zig: zig at ${ZIG_EXECUTABLE}")

# add_zig_object(<zephyr-target> <zig-source>
#                [MODULES name=path [name=path ...]])
#
# Compiles <zig-source> with `zig build-obj` using Zephyr's INTERFACE
# include directories + compile definitions (via the canonical
# `zephyr_get_*_for_lang` helpers) and a per-target libc paths file
# (`--libc`) pointing Zig's clang at zephyr-sdk's per-target sysroot.
# Then adds the resulting object as a source of <zephyr-target>.
#
# A `build_config` Zig module is auto-generated and made importable —
# carries Zephyr Kconfig values that Zig sources can read at comptime
# (e.g. `@import("build_config").ticks_per_sec`).
#
# Additional `-M` modules can be passed via MODULES, in name=path form.
# Every user module also gets the *other* user modules + build_config
# in its import table — so a higher-level module like zephyr.zig can
# `@import("timing")` without the caller spelling out the dep graph.
# Zig 0.16 forbids @import of files outside the root module's directory
# tree, so cross-directory file sharing has to go through the module
# system.
#
# The Zig optimization mode comes from CONFIG_ZIG_OPTIMIZE.
function(add_zig_object zephyr_target zig_source)
  cmake_parse_arguments(ARG "" "" "MODULES" ${ARGN})

  get_filename_component(_bin_dir "${CMAKE_C_COMPILER}" DIRECTORY)
  get_filename_component(_toolchain_root "${_bin_dir}" DIRECTORY)
  get_filename_component(_target_triple "${_toolchain_root}" NAME)
  set(_sysroot_include "${_toolchain_root}/${_target_triple}/include")

  if(NOT EXISTS "${_sysroot_include}")
    message(FATAL_ERROR
      "zephyr-lang-zig: derived sysroot include '${_sysroot_include}' does not exist. "
      "The zephyr-sdk layout assumption (gnu/<triple>/<triple>/include) doesn't "
      "match this toolchain. Extend zig.cmake with a fallback for your layout.")
  endif()

  # crt_dir must be non-empty even for build-obj — Zig's libc-paths
  # parser refuses an empty value for freestanding. We point at the
  # toolchain lib dir containing crt0.o; we never actually link CRT
  # (Zephyr provides its own startup).
  set(_libc_txt "${CMAKE_CURRENT_BINARY_DIR}/zig_libc.txt")
  set(_sysroot_lib "${_toolchain_root}/${_target_triple}/lib")
  file(WRITE "${_libc_txt}"
    "include_dir=${_sysroot_include}\n"
    "sys_include_dir=${_sysroot_include}\n"
    "crt_dir=${_sysroot_lib}\n"
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

  # Parse user modules into parallel name+path lists.
  set(_user_mod_names)
  set(_user_mod_paths)
  foreach(_module ${ARG_MODULES})
    if(NOT _module MATCHES "^([^=]+)=(.+)$")
      message(FATAL_ERROR
        "add_zig_object: MODULES entry '${_module}' must be 'name=path'")
    endif()
    set(_mod_name "${CMAKE_MATCH_1}")
    get_filename_component(_mod_path "${CMAKE_MATCH_2}" ABSOLUTE)
    # Generated modules (e.g. dt.zig from edt.pickle) don't exist at
    # configure time but will by the time zig build-obj runs — ninja
    # sequences through the file dependency. Only flag missing sources
    # under the source tree.
    if(NOT EXISTS "${_mod_path}" AND NOT "${_mod_path}" MATCHES "^${CMAKE_BINARY_DIR}")
      message(FATAL_ERROR
        "add_zig_object: module '${_mod_name}' path '${_mod_path}' does not exist")
    endif()
    list(APPEND _user_mod_names "${_mod_name}")
    list(APPEND _user_mod_paths "${_mod_path}")
  endforeach()

  # Build the --dep / -M argument chain. Zig 0.16: each `--dep X`
  # accumulates onto the next `-M`'s import table; the `-M` then
  # declares the module.
  #   Root module: --dep build_config + --dep for each user module
  #   Each user module: --dep build_config + --dep for every *other*
  #     user module — lets a higher-level module like zephyr.zig
  #     `@import("timing")` without callers having to know the dep
  #     graph. build_config and self are excluded from self-deps.
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
      -fno-PIC
      -fno-PIE
      -fno-stack-check
      -freference-trace
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
