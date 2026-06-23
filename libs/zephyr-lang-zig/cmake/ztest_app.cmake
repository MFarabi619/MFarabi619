function(zig_sample_app)
  cmake_parse_arguments(ARG "" "ZIG_SOURCE;BUILD_FILE" "EXTRA_OUTPUTS" ${ARGN})
  if(NOT ARG_ZIG_SOURCE)
    set(ARG_ZIG_SOURCE src/main.zig)
  endif()
  _zig_generate_dt(_dt_zig)
  set_target_properties(app PROPERTIES LINKER_LANGUAGE C)
  set(_build_file_arg)
  if(ARG_BUILD_FILE)
    set(_build_file_arg BUILD_FILE ${ARG_BUILD_FILE})
  endif()
  set(_extra_outputs_arg)
  if(ARG_EXTRA_OUTPUTS)
    set(_extra_outputs_arg EXTRA_OUTPUTS ${ARG_EXTRA_OUTPUTS})
  endif()
  add_zig_object(app ${ARG_ZIG_SOURCE} DT ${_dt_zig} ${_build_file_arg} ${_extra_outputs_arg})
endfunction()

function(zig_ztest_app)
  cmake_parse_arguments(ARG "" "SUITE;ZIG_SOURCE" "" ${ARGN})

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

  _zig_generate_dt(_dt_zig)

  set_target_properties(app PROPERTIES LINKER_LANGUAGE C)
  target_sources(app PRIVATE ${_gen_c} ${ZIG_MODULE_DIR}/tests/bridge_assert.c)

  set(_test_bridge "${CMAKE_CURRENT_SOURCE_DIR}/src/test_bridge.c")
  if(EXISTS "${_test_bridge}")
    target_sources(app PRIVATE ${_test_bridge})
  endif()

  add_zig_object(app ${ARG_ZIG_SOURCE} DT ${_dt_zig})
endfunction()

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
  set(${out_var} "${_dt_zig}")
endmacro()
