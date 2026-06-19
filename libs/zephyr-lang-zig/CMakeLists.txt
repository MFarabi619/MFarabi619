if(CONFIG_ZIG)
  set(ZIG_MODULE_DIR ${CMAKE_CURRENT_LIST_DIR} CACHE INTERNAL "")
  include(${CMAKE_CURRENT_LIST_DIR}/cmake/zig-target.cmake)
  include(${CMAKE_CURRENT_LIST_DIR}/cmake/zig.cmake)
  include(${CMAKE_CURRENT_LIST_DIR}/cmake/ztest_app.cmake)

  zephyr_library_named(zig_bridge)
  zephyr_library_sources(${CMAKE_CURRENT_LIST_DIR}/bridge.c)
endif()
