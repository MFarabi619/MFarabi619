if(CONFIG_SQLITE)
  zephyr_library_named(zephyr_lib_sqlite)

  zephyr_library_sources(
    ${ZEPHYR_CURRENT_MODULE_DIR}/sqlite3.c
    ${ZEPHYR_CURRENT_MODULE_DIR}/vfs.c
    ${ZEPHYR_CURRENT_MODULE_DIR}/init.c
  )
  if(CONFIG_ZTEST)
    zephyr_library_sources(${ZEPHYR_CURRENT_MODULE_DIR}/tests.c)
  endif()
  zephyr_library_sources_ifdef(CONFIG_SQLITE_SHELL
    ${ZEPHYR_CURRENT_MODULE_DIR}/shell.c
  )
  zephyr_include_directories(${ZEPHYR_CURRENT_MODULE_DIR})
  zephyr_library_compile_definitions(SQLITE_CUSTOM_INCLUDE=sqlite_config.h)
  set_source_files_properties(
    ${ZEPHYR_CURRENT_MODULE_DIR}/sqlite3.c
    PROPERTIES COMPILE_FLAGS "-w"
  )
endif()
