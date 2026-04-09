#ifndef HELPERS_H
#define HELPERS_H

#include "config.h"
#include <stddef.h>
#include <Wire.h>

int scan_i2c_bus(TwoWire &bus, char *buf, size_t buf_size);
int format_uptime(char *buf, size_t buf_size);
int format_heap(char *buf, size_t buf_size);

#endif // HELPERS_H
