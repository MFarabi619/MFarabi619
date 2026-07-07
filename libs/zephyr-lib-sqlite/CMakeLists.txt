if(CONFIG_SQLITE)
  include(FetchContent)
  FetchContent_Declare(sqlite_amalgamation
    URL      https://sqlite.org/2026/sqlite-amalgamation-3530200.zip
    URL_HASH SHA256=8a310d0a16c7a90cacd4c884e70faa51c902afed2a89f63aaa0126ab83558a32
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  )
  FetchContent_MakeAvailable(sqlite_amalgamation)

  zephyr_library_named(zephyr_lib_sqlite)

  zephyr_library_sources(
    ${sqlite_amalgamation_SOURCE_DIR}/sqlite3.c
    ${ZEPHYR_CURRENT_MODULE_DIR}/vfs.c
    ${ZEPHYR_CURRENT_MODULE_DIR}/init.c
  )
  if(CONFIG_ZTEST AND CONFIG_RUST)
    zephyr_library_sources(${ZEPHYR_CURRENT_MODULE_DIR}/tests.c)
  endif()
  zephyr_library_sources_ifdef(CONFIG_SQLITE_SHELL
    ${ZEPHYR_CURRENT_MODULE_DIR}/shell.c
  )
  zephyr_include_directories(
    ${ZEPHYR_CURRENT_MODULE_DIR}
    ${sqlite_amalgamation_SOURCE_DIR}
  )
  zephyr_library_compile_definitions(SQLITE_CUSTOM_INCLUDE=sqlite_config.h)
  set_source_files_properties(
    ${sqlite_amalgamation_SOURCE_DIR}/sqlite3.c
    PROPERTIES COMPILE_FLAGS "-w"
  )
endif()
