#include "../../../config.h"
#include "../../../hardware/i2c.h"

#include <Arduino.h>
#include <Wire.h>
#include <microshell.h>
#include <string.h>

//------------------------------------------
//  /dev/bus/scan — full I2C bus + mux scan
//------------------------------------------
static size_t scan_get_data(struct ush_object *self,
                            struct ush_file_descriptor const *file,
                            uint8_t **data) {
  (void)self; (void)file;
  static char buf[1536];

  hardware::i2c::ScanCommand command = {
    .buffer = buf,
    .capacity = sizeof(buf),
    .length = 0,
  };
  hardware::i2c::scan(&command);
  *data = (uint8_t *)buf;
  return strlen(buf);
}

static const struct ush_file_descriptor bus_files[] = {
  { .name = "scan",  .description = "I2C bus + mux scan",
    .get_data = scan_get_data },
  { .name = "rs485", .description = "RS485 Modbus",
    .help = "not implemented yet\r\n" },
};

static struct ush_node_object bus;

void dev_bus_mount(struct ush_object *ush) {
  hardware::i2c::initialize();
  ush_node_mount(ush, "/dev/bus", &bus, bus_files,
                 sizeof(bus_files) / sizeof(bus_files[0]));
}
