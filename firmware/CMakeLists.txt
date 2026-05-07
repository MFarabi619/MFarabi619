# SPDX-License-Identifier: Apache-2.0

rust_cargo_application(CRATE_NAME firmware FEATURES zephyr)

target_sources(app PRIVATE
  src/boot.c
  src/console/prompt.c
  src/console/fs_aliases.c
  src/services/http/provisioning.c
  src/services/sdcard.c
  src/services/http/filesystem.c
  src/services/mqtt.c
  src/services/mcumgr.c
  src/services/prometheus.c
  src/services/diagnostics.c
  src/services/http/api.c
  src/sensors/devices.c
  src/sensors/soil_moisture.c
  src/sensors/soil_moisture_three_in_one.c
)

target_include_directories(app PRIVATE include)

zephyr_linker_sources(SECTIONS
  linker/discard_defmt.ld
  linker/http-resources.ld
)

zephyr_linker_section(NAME http_resource_desc_provisioning_service
                      KVMA RAM_REGION GROUP RODATA_REGION)
