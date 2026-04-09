#include "helpers.h"

#include <Arduino.h>
#include <stdio.h>

// Clamp pos to buf_size-1 after snprintf (which returns would-be length)
static inline int clamp_pos(int pos, size_t buf_size) {
  return (pos >= (int)buf_size) ? (int)buf_size - 1 : pos;
}

int scan_i2c_bus(TwoWire &bus, char *buf, size_t buf_size) {
  int pos = 0;
  int found = 0;
  for (uint8_t addr = CONFIG_I2C_ADDR_MIN;
       addr < CONFIG_I2C_ADDR_MAX && pos < (int)buf_size - 16; addr++) {
    bus.beginTransmission(addr);
    if (bus.endTransmission() == 0) {
      pos += snprintf(buf + pos, buf_size - pos, "  0x%02X\r\n", addr);
      pos = clamp_pos(pos, buf_size);
      found++;
    }
  }
  if (found == 0)
    pos += snprintf(buf + pos, buf_size - pos, "  (no devices)\r\n");
  else
    pos += snprintf(buf + pos, buf_size - pos, "%d device(s)\r\n", found);
  pos = clamp_pos(pos, buf_size);
  return pos;
}

int format_uptime(char *buf, size_t buf_size) {
  unsigned long secs = millis() / 1000;
  return snprintf(buf, buf_size, "%luh %lum %lus\r\n",
                  secs / 3600, (secs / 60) % 60, secs % 60);
}

int format_heap(char *buf, size_t buf_size) {
  return snprintf(buf, buf_size,
                  "heap total: %u\r\nheap free:  %u\r\nheap used:  %u\r\n",
                  ESP.getHeapSize(), ESP.getFreeHeap(),
                  ESP.getHeapSize() - ESP.getFreeHeap());
}
