#include "../../../config.h"
#include "../../../drivers/ds3231.h"

#include <Arduino.h>
#include <Wire.h>
#include <microshell.h>
#include <string.h>

//------------------------------------------
//  /dev/sensors/i2c_scan
//------------------------------------------
static size_t i2c_scan_get_data(struct ush_object *self,
                                struct ush_file_descriptor const *file,
                                uint8_t **data) {
  (void)self; (void)file;
  static char buf[512];
  int pos = 0;
  int found = 0;

  pos += snprintf(buf + pos, sizeof(buf) - pos, "bus 0:\r\n");
  for (uint8_t addr = CONFIG_I2C_ADDR_MIN; addr < CONFIG_I2C_ADDR_MAX && pos < (int)sizeof(buf) - 16; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      pos += snprintf(buf + pos, sizeof(buf) - pos, "  0x%02X\r\n", addr);
      found++;
    }
  }

  int remaining = sizeof(buf) - pos;
  if (remaining > 16) {
    pos += snprintf(buf + pos, remaining, "bus 1:\r\n");
    for (uint8_t addr = CONFIG_I2C_ADDR_MIN; addr < CONFIG_I2C_ADDR_MAX && pos < (int)sizeof(buf) - 16; addr++) {
      Wire1.beginTransmission(addr);
      if (Wire1.endTransmission() == 0) {
        pos += snprintf(buf + pos, sizeof(buf) - pos, "  0x%02X\r\n", addr);
        found++;
      }
    }
  }

  if (pos < (int)sizeof(buf) - 32)
    pos += snprintf(buf + pos, sizeof(buf) - pos, "%d device(s) total\r\n", found);

  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /dev/sensors/rtc
//------------------------------------------
static size_t rtc_get_data(struct ush_object *self,
                           struct ush_file_descriptor const *file,
                           uint8_t **data) {
  (void)self; (void)file;
  static char buf[64];
  if (!ds3231_oscillator_ok()) {
    snprintf(buf, sizeof(buf), "(oscillator stopped — time invalid)\r\n");
  } else {
    snprintf(buf, sizeof(buf), "%s\r\n", ds3231_time_string());
  }
  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /dev/sensors/temperature
//------------------------------------------
static size_t temperature_get_data(struct ush_object *self,
                                   struct ush_file_descriptor const *file,
                                   uint8_t **data) {
  (void)self; (void)file;
  static char buf[32];
  float temp = ds3231_temperature();
  snprintf(buf, sizeof(buf), "%.2f C\r\n", temp);
  *data = (uint8_t *)buf;
  return strlen(buf);
}

static const struct ush_file_descriptor sensors_files[] = {
  { .name = "i2c_scan",    .description = "scan all I2C buses",
    .get_data = i2c_scan_get_data },
  { .name = "rtc",         .description = "DS3231 date/time",
    .get_data = rtc_get_data },
  { .name = "temperature", .description = "DS3231 temperature",
    .get_data = temperature_get_data },
};

static struct ush_node_object sensors_node;

void dev_sensors_mount(struct ush_object *ush) {
  ds3231_init();
  ush_node_mount(ush, "/dev/sensors", &sensors_node, sensors_files,
                 sizeof(sensors_files) / sizeof(sensors_files[0]));
}
