cmake_minimum_required(VERSION 3.20.0)

set(WORKSPACE_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../..)
set(WALTER_ROUTER_LIB ${WORKSPACE_ROOT}/libs/walter-router)
set(SHARED_CONF ${WORKSPACE_ROOT}/libs/firmware/conf)

set(KCONFIG_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/Kconfig)
set(APPLICATION_CONFIG_DIR ${CMAKE_CURRENT_SOURCE_DIR})

list(APPEND EXTRA_CONF_FILE
  ${SHARED_CONF}/base.conf
  ${SHARED_CONF}/log.conf
  ${SHARED_CONF}/shell.conf
  ${SHARED_CONF}/net.conf
  ${SHARED_CONF}/wifi.conf
  ${SHARED_CONF}/dns.conf
  # ${CMAKE_CURRENT_SOURCE_DIR}/ssh.conf   # disabled — wolfssh/wolfssl freezing UART shell
  ${SHARED_CONF}/mcumgr.conf
  ${SHARED_CONF}/storage.conf
  ${SHARED_CONF}/debug.conf
  ${SHARED_CONF}/pm.conf
  ${SHARED_CONF}/task_wdt.conf
)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(walter-router)

add_subdirectory(${WALTER_ROUTER_LIB} ${CMAKE_BINARY_DIR}/walter-router-lib)

if(CONFIG_WOLFSSH)
  zephyr_include_directories(${CMAKE_CURRENT_SOURCE_DIR})
endif()
