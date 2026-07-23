if(CONFIG_SH8601 OR CONFIG_MIPI_DBI_ESP32_QSPI)
  zephyr_library()
  zephyr_library_sources_ifdef(CONFIG_SH8601 src/sh8601.c)
  zephyr_library_sources_ifdef(CONFIG_MIPI_DBI_ESP32_QSPI src/mipi_dbi_esp32_qspi.c)

  if(CONFIG_MIPI_DBI_ESP32_QSPI AND NOT CONFIG_ESP32_SPIM)
    set(ESP_HAL_GPSPI_DIR ${ZEPHYR_HAL_ESPRESSIF_MODULE_DIR}/components/esp_hal_gpspi)
    zephyr_library_sources(
      ${ESP_HAL_GPSPI_DIR}/spi_hal.c
      ${ESP_HAL_GPSPI_DIR}/${CONFIG_SOC_SERIES}/spi_periph.c
      ${ESP_HAL_GPSPI_DIR}/spi_hal_iram.c
    )
  endif()
endif()
