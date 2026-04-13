#ifndef SERVICES_DATA_LOGGER_H
#define SERVICES_DATA_LOGGER_H

#include <stdint.h>

struct DataLoggerStatusSnapshot {
  bool initialized;
  bool sd_ready;
  bool header_written;
  uint32_t interval_ms;
  uint32_t last_log_ms;
  const char *path;
  uint32_t ring_buf_used;
  uint32_t ring_buf_capacity;
  bool ring_buf_overrun;
};

namespace services::data_logger {

void initialize();
void service();
void flushNow();
bool accessStatus(DataLoggerStatusSnapshot *snapshot);

}

#endif
