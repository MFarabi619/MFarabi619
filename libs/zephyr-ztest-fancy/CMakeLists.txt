zephyr_library_named(ztest_fancy)

if(CONFIG_ZTEST_FANCY)
  zephyr_include_directories(${ZEPHYR_CURRENT_MODULE_DIR}/include)
  zephyr_library_sources(${ZEPHYR_CURRENT_MODULE_DIR}/main.c)
endif()
