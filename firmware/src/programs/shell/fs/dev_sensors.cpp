#include "../../../config.h"
#include "../../../hardware/i2c.h"
#include "../../../sensors/manager.h"
#include "../../../services/rtc.h"

#include <Arduino.h>
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
  hardware::i2c::ScanCommand command = {
    .buffer = buf,
    .capacity = sizeof(buf),
    .length = 0,
  };
  hardware::i2c::scan(&command);

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
  RTCSnapshot snapshot = {};
  if (!services::rtc::accessSnapshot(&snapshot) || !snapshot.valid) {
    snprintf(buf, sizeof(buf), "(oscillator stopped — time invalid)\r\n");
  } else {
    snprintf(buf, sizeof(buf), "%s\r\n", snapshot.iso8601);
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
  RTCSnapshot snapshot = {};
  services::rtc::accessSnapshot(&snapshot);
  snprintf(buf, sizeof(buf), "%.2f C\r\n", snapshot.temperature_celsius);
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
  services::rtc::initialize();
  sensors::manager::initialize();
  ush_node_mount(ush, "/dev/sensors", &sensors_node, sensors_files,
                 sizeof(sensors_files) / sizeof(sensors_files[0]));
}
