if(BOARD MATCHES "^walter")
  set(mcuboot_EXTRA_CONF_FILE ${CMAKE_CURRENT_LIST_DIR}/sysbuild/mcuboot_walter.conf
      CACHE INTERNAL "per-board mcuboot conf"
  )
elseif(BOARD MATCHES "^xiao_esp32s3")
  set(mcuboot_EXTRA_CONF_FILE ${CMAKE_CURRENT_LIST_DIR}/sysbuild/mcuboot_xiao_esp32s3.conf
      CACHE INTERNAL "per-board mcuboot conf"
  )
endif()
