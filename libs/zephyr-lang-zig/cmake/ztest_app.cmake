function(zig_sample_app)
  cmake_parse_arguments(ARG "" "ZIG_SOURCE" "ZIG_MODULES" ${ARGN})
  if(NOT ARG_ZIG_SOURCE)
    set(ARG_ZIG_SOURCE src/main.zig)
  endif()
  _zig_apply_lib_modules(ARG_ZIG_MODULES)

  set_target_properties(app PROPERTIES LINKER_LANGUAGE C)
  add_zig_object(app ${ARG_ZIG_SOURCE} MODULES ${ARG_ZIG_MODULES})
endfunction()

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

  set(_gen_c "${CMAKE_CURRENT_BINARY_DIR}/test_main.c")
  add_custom_command(
    OUTPUT ${_gen_c}
    COMMAND ${Python3_EXECUTABLE} ${ZIG_MODULE_DIR}/scripts/gen_test_main.py
      --zig-source ${_zig_abs}
      --suite ${ARG_SUITE}
      --output ${_gen_c}
    DEPENDS ${_zig_abs} ${ZIG_MODULE_DIR}/scripts/gen_test_main.py
    VERBATIM
    COMMENT "gen_test_main ${ARG_SUITE} from ${ARG_ZIG_SOURCE}"
  )

  _zig_apply_lib_modules(ARG_ZIG_MODULES)

  set_target_properties(app PROPERTIES LINKER_LANGUAGE C)
  target_sources(app PRIVATE ${_gen_c} ${ZIG_MODULE_DIR}/tests/bridge_assert.c)

  set(_test_bridge "${CMAKE_CURRENT_SOURCE_DIR}/src/test_bridge.c")
  if(EXISTS "${_test_bridge}")
    target_sources(app PRIVATE ${_test_bridge})
  endif()

  add_zig_object(app ${ARG_ZIG_SOURCE} MODULES ${ARG_ZIG_MODULES})
endfunction()

macro(_zig_apply_lib_modules out_var)
  _zig_generate_dt(_dt_module_spec)
  set(_lib_dir ${ZIG_MODULE_DIR}/lib)
  list(APPEND ${out_var}
    timing=${_lib_dir}/timing.zig
    ring_buffer=${_lib_dir}/ring_buffer.zig
    zephyr=${_lib_dir}/zephyr.zig
    test_helpers=${_lib_dir}/test_helpers.zig
    ${_dt_module_spec}
  )
endmacro()

macro(_zig_generate_dt out_var)
  set(_dt_zig "${CMAKE_CURRENT_BINARY_DIR}/zig_dt.zig")
  add_custom_command(
    OUTPUT ${_dt_zig}
    COMMAND ${Python3_EXECUTABLE} ${ZIG_MODULE_DIR}/scripts/gen_dts_zig.py
      --zig-out ${_dt_zig}
      --edt-pickle ${EDT_PICKLE}
      --edt-lib ${ZEPHYR_BASE}/scripts/dts/python-devicetree/src
    DEPENDS ${EDT_PICKLE} ${ZIG_MODULE_DIR}/scripts/gen_dts_zig.py
    VERBATIM
    COMMENT "gen_dts_zig ${_dt_zig}"
  )
  set(${out_var} "dt=${_dt_zig}")
endmacro()
