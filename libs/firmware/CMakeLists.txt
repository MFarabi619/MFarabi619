zephyr_library_named(firmware)

if(CONFIG_ZTEST)
  zephyr_include_directories(${ZEPHYR_CURRENT_MODULE_DIR}/include)
endif()

if(CONFIG_FILE_SYSTEM AND CONFIG_ZTEST)
  zephyr_library_sources(${ZEPHYR_CURRENT_MODULE_DIR}/filesystems/tests.c)
endif()

if(CONFIG_SHELL_ALIASES_HAS_FILE)
  generate_shell_aliases_inc_file_for_target(
    app
    ${ZEPHYR_CURRENT_MODULE_DIR}/programs/shell.aliases.txt
    ${ZEPHYR_BINARY_DIR}/include/generated/generated-shell-aliases.inc
  )
endif()

zephyr_library_sources_ifdef(CONFIG_NET_DHCPV4_SERVER
  ${ZEPHYR_CURRENT_MODULE_DIR}/networking/dns/proxy.c
)
set_source_files_properties(
  ${ZEPHYR_CURRENT_MODULE_DIR}/networking/dns/proxy.c
  PROPERTIES INCLUDE_DIRECTORIES "${ZEPHYR_BASE}/subsys/net/lib/dns"
)

zephyr_library_sources_ifdef(CONFIG_WIREGUARD
  ${ZEPHYR_CURRENT_MODULE_DIR}/networking/wireguard/wireguard.c
)
if(CONFIG_WIREGUARD)
  zephyr_library_include_directories(${ZEPHYR_BASE}/subsys/net/lib/wireguard)
endif()

zephyr_library_sources_ifdef(CONFIG_HTTP_SERVER
  ${ZEPHYR_CURRENT_MODULE_DIR}/services/http/http.c
)
if(CONFIG_HTTP_SERVER)
  zephyr_linker_sources(SECTIONS ${ZEPHYR_CURRENT_MODULE_DIR}/services/http/http_sections.ld)
endif()

zephyr_library_sources_ifdef(CONFIG_SQLITE
  ${ZEPHYR_CURRENT_MODULE_DIR}/programs/sqlite/sqlite3.c
  ${ZEPHYR_CURRENT_MODULE_DIR}/programs/sqlite/vfs.c
  ${ZEPHYR_CURRENT_MODULE_DIR}/programs/sqlite/init.c
)
if(CONFIG_SQLITE AND CONFIG_ZTEST)
  zephyr_library_sources(${ZEPHYR_CURRENT_MODULE_DIR}/programs/sqlite/tests.c)
endif()
zephyr_library_sources_ifdef(CONFIG_SQLITE_SHELL
  ${ZEPHYR_CURRENT_MODULE_DIR}/programs/sqlite/shell.c
)
if(CONFIG_SQLITE)
  zephyr_include_directories(${ZEPHYR_CURRENT_MODULE_DIR}/programs/sqlite)
  zephyr_library_compile_definitions(SQLITE_CUSTOM_INCLUDE=sqlite_config.h)
  set_source_files_properties(
    ${ZEPHYR_CURRENT_MODULE_DIR}/programs/sqlite/sqlite3.c
    PROPERTIES COMPILE_FLAGS "-w"
  )
endif()
