# zig_sample_app([ZIG_SOURCE <file>]
#                              [ZIG_MODULES name=path [name=path ...]])
function(zig_sample_app)
  cmake_parse_arguments(ARG "" "ZIG_SOURCE" "ZIG_MODULES" ${ARGN})
  if(NOT ARG_ZIG_SOURCE)
    set(ARG_ZIG_SOURCE src/main.zig)
  endif()
  _zig_apply_lib_modules(ARG_ZIG_MODULES)

  set_target_properties(app PROPERTIES LINKER_LANGUAGE C)
  add_zig_object(app ${ARG_ZIG_SOURCE} MODULES ${ARG_ZIG_MODULES})
endfunction()

# zig_ztest_app([SUITE <name>]
#                            [ZIG_SOURCE <file>]
#                            [ZIG_MODULES name=path [name=path ...]])
#
# Standard Zephyr ztest app shape — auto-generates test_main.c from the
# `export fn zig_test_*` declarations in <ZIG_SOURCE>. If a sibling
# src/test_bridge.c exists, it's added too (for test-specific C-side
# helpers like K_MUTEX_DEFINE'd statics).
#
# Defaults:
#   SUITE       derived from directory name (ztest_X → zig_X)
#   ZIG_SOURCE  src/zig_tests.zig
function(zig_ztest_app)
  cmake_parse_arguments(ARG "" "SUITE;ZIG_SOURCE" "ZIG_MODULES" ${ARGN})

  if(NOT ARG_SUITE)
    get_filename_component(_dir_name ${CMAKE_CURRENT_SOURCE_DIR} NAME)
    string(REGEX REPLACE "^ztest_" "" _suite_short "${_dir_name}")
    set(ARG_SUITE "zig_${_suite_short}")
  endif()

  if(NOT ARG_ZIG_SOURCE)
    set(ARG_ZIG_SOURCE src/zig_tests.zig)
  endif()
  get_filename_component(_zig_abs "${ARG_ZIG_SOURCE}" ABSOLUTE)

  set(_generator "${ZIG_MODULE_DIR}/scripts/gen_test_main.py")
  set(_gen_c "${CMAKE_CURRENT_BINARY_DIR}/test_main.c")

  add_custom_command(
    OUTPUT ${_gen_c}
    COMMAND ${Python3_EXECUTABLE} ${_generator}
      --zig-source ${_zig_abs}
      --suite ${ARG_SUITE}
      --output ${_gen_c}
    DEPENDS ${_zig_abs} ${_generator}
    VERBATIM
    COMMENT "gen_test_main ${ARG_SUITE} from ${ARG_ZIG_SOURCE}"
  )

  _zig_apply_lib_modules(ARG_ZIG_MODULES)

  set_target_properties(app PROPERTIES LINKER_LANGUAGE C)
  target_sources(app PRIVATE ${_gen_c})

  # Optional test-specific C bridge (for K_MUTEX_DEFINE'd statics etc.)
  set(_test_bridge "${CMAKE_CURRENT_SOURCE_DIR}/src/test_bridge.c")
  if(EXISTS "${_test_bridge}")
    target_sources(app PRIVATE ${_test_bridge})
  endif()

  add_zig_object(app ${ARG_ZIG_SOURCE} MODULES ${ARG_ZIG_MODULES})
endfunction()

# Internal: prepend the lib/ modules + generated dt module to <out_var>
# unless already present.
macro(_zig_apply_lib_modules out_var)
  _zig_generate_dt(_dt_module_spec)

  set(_lib_dir ${ZIG_MODULE_DIR}/lib)
  set(_lib_modules
    timing=${_lib_dir}/timing.zig
    ring_buffer=${_lib_dir}/ring_buffer.zig
    zephyr=${_lib_dir}/zephyr.zig
    test_helpers=${_lib_dir}/test_helpers.zig
    ${_dt_module_spec}
  )
  foreach(_default ${_lib_modules})
    string(REGEX MATCH "^([^=]+)=" _ ${_default})
    set(_name ${CMAKE_MATCH_1})
    set(_already_present FALSE)
    foreach(_user ${${out_var}})
      if(_user MATCHES "^${_name}=")
        set(_already_present TRUE)
        break()
      endif()
    endforeach()
    if(NOT _already_present)
      list(APPEND ${out_var} ${_default})
    endif()
  endforeach()
endmacro()

# Internal: generate dt.zig from the build's edt.pickle and set
# <out_var> to "dt=<path>". Depends on EDT_PICKLE, which Zephyr exports
# after DTS processing — the custom command sequences after that target.
macro(_zig_generate_dt out_var)
  set(_dt_zig "${CMAKE_CURRENT_BINARY_DIR}/zig_dt.zig")
  set(_dt_script "${ZIG_MODULE_DIR}/scripts/gen_dts_zig.py")
  set(_edt_lib "${ZEPHYR_BASE}/scripts/dts/python-devicetree/src")

  add_custom_command(
    OUTPUT ${_dt_zig}
    COMMAND ${Python3_EXECUTABLE} ${_dt_script}
      --zig-out ${_dt_zig}
      --edt-pickle ${EDT_PICKLE}
      --edt-lib ${_edt_lib}
    DEPENDS ${EDT_PICKLE} ${_dt_script}
    VERBATIM
    COMMENT "gen_dts_zig ${_dt_zig}"
  )

  set(${out_var} "dt=${_dt_zig}")
endmacro()
