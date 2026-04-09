#include <Arduino.h>
#include <Wire.h>
#include <microshell.h>
#include <string.h>

//------------------------------------------
//  /dev/bus/i2c0 — I2C bus 0 scan
//------------------------------------------
static size_t i2c0_get_data(struct ush_object *self,
                            struct ush_file_descriptor const *file,
                            uint8_t **data) {
  (void)self; (void)file;
  static char buf[512];
  int pos = 0;
  int found = 0;

  pos += snprintf(buf + pos, sizeof(buf) - pos, "I2C bus 0 scan:\r\n");
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      pos += snprintf(buf + pos, sizeof(buf) - pos, "  0x%02X\r\n", addr);
      found++;
    }
  }
  if (found == 0)
    pos += snprintf(buf + pos, sizeof(buf) - pos, "  (no devices)\r\n");
  else
    pos += snprintf(buf + pos, sizeof(buf) - pos, "%d device(s)\r\n", found);

  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /dev/bus/i2c1 — I2C bus 1 scan
//------------------------------------------
static size_t i2c1_get_data(struct ush_object *self,
                            struct ush_file_descriptor const *file,
                            uint8_t **data) {
  (void)self; (void)file;
  static char buf[512];
  int pos = 0;
  int found = 0;

  pos += snprintf(buf + pos, sizeof(buf) - pos, "I2C bus 1 scan:\r\n");
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire1.beginTransmission(addr);
    if (Wire1.endTransmission() == 0) {
      pos += snprintf(buf + pos, sizeof(buf) - pos, "  0x%02X\r\n", addr);
      found++;
    }
  }
  if (found == 0)
    pos += snprintf(buf + pos, sizeof(buf) - pos, "  (no devices)\r\n");
  else
    pos += snprintf(buf + pos, sizeof(buf) - pos, "%d device(s)\r\n", found);

  *data = (uint8_t *)buf;
  return strlen(buf);
}

static const struct ush_file_descriptor bus_files[] = {
  { .name = "i2c0",  .description = "I2C bus 0 scan",
    .get_data = i2c0_get_data },
  { .name = "i2c1",  .description = "I2C bus 1 scan",
    .get_data = i2c1_get_data },
  { .name = "rs485", .description = "RS485 Modbus",
    .help = "not implemented yet\r\n" },
};

static struct ush_node_object bus;

void dev_bus_mount(struct ush_object *ush) {
  ush_node_mount(ush, "/dev/bus", &bus, bus_files,
                 sizeof(bus_files) / sizeof(bus_files[0]));
}
