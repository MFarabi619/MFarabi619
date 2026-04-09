#include "../../../config.h"
#include "../../../helpers.h"
#include "../../../drivers/tca9548a.h"

#include <Arduino.h>
#include <Wire.h>
#include <microshell.h>
#include <string.h>

//------------------------------------------
//  /dev/bus/i2c0
//------------------------------------------
static size_t i2c0_get_data(struct ush_object *self,
                            struct ush_file_descriptor const *file,
                            uint8_t **data) {
  (void)self; (void)file;
  static char buf[512];
  scan_i2c_bus(Wire, buf, sizeof(buf));
  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /dev/bus/i2c1
//------------------------------------------
static size_t i2c1_get_data(struct ush_object *self,
                            struct ush_file_descriptor const *file,
                            uint8_t **data) {
  (void)self; (void)file;
  static char buf[512];
  scan_i2c_bus(Wire1, buf, sizeof(buf));
  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /dev/bus/mux — TCA9548A per-channel scan
//------------------------------------------
static size_t mux_get_data(struct ush_object *self,
                           struct ush_file_descriptor const *file,
                           uint8_t **data) {
  (void)self; (void)file;
  static char buf[1024];

  if (!tca9548a_is_connected()) {
    snprintf(buf, sizeof(buf), "(mux not connected)\r\n");
    *data = (uint8_t *)buf;
    return strlen(buf);
  }

  tca9548a_scan_all(buf, sizeof(buf));
  *data = (uint8_t *)buf;
  return strlen(buf);
}

static const struct ush_file_descriptor bus_files[] = {
  { .name = "i2c0",  .description = "I2C bus 0 scan",
    .get_data = i2c0_get_data },
  { .name = "i2c1",  .description = "I2C bus 1 scan",
    .get_data = i2c1_get_data },
  { .name = "mux",   .description = "TCA9548A per-channel scan",
    .get_data = mux_get_data },
  { .name = "rs485", .description = "RS485 Modbus",
    .help = "not implemented yet\r\n" },
};

static struct ush_node_object bus;

void dev_bus_mount(struct ush_object *ush) {
  tca9548a_init();
  ush_node_mount(ush, "/dev/bus", &bus, bus_files,
                 sizeof(bus_files) / sizeof(bus_files[0]));
}
