#include "../../../config.h"
#include "../../../hardware/i2c.h"
#include "../../../networking/modbus.h"

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

static size_t rs485_get_data(struct ush_object *self,
                             struct ush_file_descriptor const *file,
                             uint8_t **data) {
  (void)self; (void)file;
  static char buf[1024];
  int pos = 0;

  for (uint8_t channel = 0; channel < config::rs485::CHANNEL_COUNT; channel++) {
    pos += snprintf(buf + pos, sizeof(buf) - pos, "rs485 bus %u:\r\n", channel);

    ModbusScanResult results[32] = {};
    ModbusScanCommand command = {
      .channel = channel == 0 ? hardware::rs485::Channel::Bus0 : hardware::rs485::Channel::Bus1,
      .first_slave_id = 1,
      .last_slave_id = 32,
      .results = results,
      .max_results = 32,
      .result_count = 0,
    };

    networking::modbus::scan(&command);
    if (command.result_count == 0) {
      pos += snprintf(buf + pos, sizeof(buf) - pos, "  (none)\r\n");
      continue;
    }

    for (size_t index = 0; index < command.result_count && pos < (int)sizeof(buf) - 16; index++) {
      pos += snprintf(buf + pos, sizeof(buf) - pos, "  slave %u\r\n",
                      results[index].slave_id);
    }
  }

  *data = (uint8_t *)buf;
  return strlen(buf);
}

static const struct ush_file_descriptor bus_files[] = {
  { .name = "scan",  .description = "I2C bus + mux scan",
     .get_data = scan_get_data },
  { .name = "rs485", .description = "RS485 Modbus",
    .get_data = rs485_get_data },
};

static struct ush_node_object bus;

void dev_bus_mount(struct ush_object *ush) {
  hardware::i2c::initialize();
  ush_node_mount(ush, "/dev/bus", &bus, bus_files,
                 sizeof(bus_files) / sizeof(bus_files[0]));
}
