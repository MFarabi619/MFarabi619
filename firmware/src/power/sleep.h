#ifndef POWER_SLEEP_H
#define POWER_SLEEP_H

#include <stdint.h>

struct SleepCommand {
  uint32_t duration_seconds;
  bool ok;
};

struct SleepConfig {
  bool enabled;
  uint32_t duration_seconds;
};

struct SleepStatusSnapshot {
  bool pending;
  uint32_t requested_duration_seconds;
  const char *wake_cause;
  bool timer_wakeup_enabled;
  uint64_t timer_wakeup_us;
  bool config_enabled;
  uint32_t default_duration_seconds;
};

namespace power::sleep {

void initialize();
bool request(SleepCommand *command);
bool requestConfigured(SleepCommand *command);
void service();
const char *accessWakeCause();
bool accessStatus(SleepStatusSnapshot *snapshot);
bool accessConfig(SleepConfig *config);
bool storeConfig(const SleepConfig *config);
void abortPending();

}

#endif
