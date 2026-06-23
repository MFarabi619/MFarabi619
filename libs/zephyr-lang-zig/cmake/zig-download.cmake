set(_zig_bootstrap_version "0.16.0-xtensa")

cmake_host_system_information(RESULT _host_os QUERY OS_NAME)
string(TOLOWER "${_host_os}" _host_os_lower)
set(_host_arch "${CMAKE_HOST_SYSTEM_PROCESSOR}")
if(NOT _host_arch)
  execute_process(COMMAND uname -m
    OUTPUT_VARIABLE _host_arch OUTPUT_STRIP_TRAILING_WHITESPACE)
endif()

if(_host_arch MATCHES "^(AMD64|amd64|x86_64|X64)$")
  set(_zig_arch "x86_64")
elseif(_host_arch MATCHES "^(aarch64|arm64|ARM64)$")
  set(_zig_arch "aarch64")
else()
  message(FATAL_ERROR
    "zephyr-lang-zig: zig-espressif-bootstrap has no prebuilt for "
    "CMAKE_HOST_SYSTEM_PROCESSOR='${CMAKE_HOST_SYSTEM_PROCESSOR}'.")
endif()

if(_host_os_lower MATCHES "(linux|unix)")
  set(_zig_platform "linux-musl")
  set(_archive_ext "tar.xz")
elseif(_host_os_lower MATCHES "darwin|mac|osx")
  set(_zig_platform "macos")
  set(_archive_ext "tar.xz")
elseif(_host_os_lower MATCHES "windows|win")
  set(_zig_platform "windows")
  set(_archive_ext "zip")
else()
  message(FATAL_ERROR "zephyr-lang-zig: unsupported host OS '${_host_os}'.")
endif()

set(_zig_triplet "${_zig_arch}-${_zig_platform}-baseline")

if(_zig_platform STREQUAL "linux-musl" AND _zig_arch STREQUAL "aarch64")
  set(_zig_sha256 "5304f43cd30dfcbdc555fde3e2b6501b4838322ba47dd71da34111e08b02eef4")
elseif(_zig_platform STREQUAL "linux-musl" AND _zig_arch STREQUAL "x86_64")
  set(_zig_sha256 "9e3dcef9d6f6d552df641a12addc9e443a69b7cbdad85492ec677acd55b7de9b")
elseif(_zig_platform STREQUAL "windows" AND _zig_arch STREQUAL "x86_64")
  set(_zig_sha256 "f515bd0a11dcb48936883575552553596f8f6b872055d19b89a874d585e445e3")
elseif(_zig_platform STREQUAL "macos" AND _zig_arch STREQUAL "aarch64")
  set(_zig_sha256 "7f5058c23ae822b9585ca054023676b7e07e48e4d1e265a6bd3104a55b0295ef")
else()
  message(FATAL_ERROR
    "zephyr-lang-zig: no pinned SHA256 for ${_zig_triplet}.")
endif()

if(DEFINED ENV{ZEPHYR_LANG_ZIG_CACHE})
  set(_cache_root "$ENV{ZEPHYR_LANG_ZIG_CACHE}")
elseif(DEFINED ENV{XDG_CACHE_HOME})
  set(_cache_root "$ENV{XDG_CACHE_HOME}/zephyr-lang-zig")
elseif(CMAKE_HOST_WIN32 AND DEFINED ENV{LOCALAPPDATA})
  set(_cache_root "$ENV{LOCALAPPDATA}/zephyr-lang-zig/cache")
elseif(DEFINED ENV{HOME})
  set(_cache_root "$ENV{HOME}/.cache/zephyr-lang-zig")
else()
  set(_cache_root "${CMAKE_CURRENT_LIST_DIR}/../.zig-bootstrap-cache")
endif()
file(MAKE_DIRECTORY "${_cache_root}")
set(_zig_dir     "${_cache_root}/zig-relsafe-${_zig_triplet}")
set(_zig_archive "${_zig_dir}.${_archive_ext}")

if(NOT EXISTS "${_zig_dir}/zig")
  set(_zig_url
    "https://github.com/kassane/zig-espressif-bootstrap/releases/download/${_zig_bootstrap_version}/zig-relsafe-${_zig_triplet}.${_archive_ext}")
  message(STATUS "zephyr-lang-zig: downloading zig-espressif-bootstrap ${_zig_bootstrap_version}")
  message(STATUS "  url: ${_zig_url}")
  message(STATUS "  to:  ${_zig_archive}")
  file(DOWNLOAD "${_zig_url}" "${_zig_archive}"
    TLS_VERIFY ON
    EXPECTED_HASH SHA256=${_zig_sha256}
    STATUS _dl_status
    LOG _dl_log
    SHOW_PROGRESS)
  list(GET _dl_status 0 _dl_code)
  if(NOT _dl_code EQUAL 0)
    message(FATAL_ERROR "zephyr-lang-zig: download failed:\n${_dl_log}")
  endif()
  message(STATUS "zephyr-lang-zig: extracting ${_archive_ext}")
  if(_host_os_lower MATCHES "windows|win")
    execute_process(
      COMMAND powershell -NoProfile -ExecutionPolicy Bypass
        -Command "Expand-Archive -Path '${_zig_archive}' -DestinationPath '${_cache_root}' -Force"
      RESULT_VARIABLE _extract_result)
  else()
    execute_process(
      COMMAND ${CMAKE_COMMAND} -E tar xf "${_zig_archive}"
      WORKING_DIRECTORY "${_cache_root}"
      RESULT_VARIABLE _extract_result)
  endif()
  if(NOT _extract_result EQUAL 0)
    message(FATAL_ERROR "zephyr-lang-zig: extraction failed (code ${_extract_result})")
  endif()
  file(REMOVE "${_zig_archive}")
else()
  message(STATUS "zephyr-lang-zig: using cached zig-espressif-bootstrap at ${_zig_dir}")
endif()

set(ZIG_BIN "${_zig_dir}/zig" CACHE FILEPATH "zig-espressif-bootstrap binary" FORCE)
message(STATUS "zephyr-lang-zig: ZIG_BIN = ${ZIG_BIN}")
