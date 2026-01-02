#ifndef SERIAL_LOGGER_UTILS_H
#define SERIAL_LOGGER_UTILS_H

#include <Arduino.h>

#define CLR_RED "\033[31m"
#define CLR_GREEN "\033[32m"
#define CLR_BLUE_B "\033[94m"
#define CLR_YELLOW "\033[33m"
#define CLR_MAGENTA_B "\033[95m"
#define CLR_RESET "\033[0m"

void begin_serial_logger();

#endif
