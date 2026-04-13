#ifndef POWER_SLEEP_H
#define POWER_SLEEP_H

#include <stdint.h>

struct SleepCommand {
  uint32_t duration_seconds;
  bool ok;
};

struct SleepStatusSnapshot {
  bool pending;
  uint32_t requested_duration_seconds;
  const char *wake_cause;
  bool timer_wakeup_enabled;
  uint64_t timer_wakeup_us;
};

namespace power::sleep {

void initialize();
bool request(SleepCommand *command);
void service();
const char *accessWakeCause();
bool accessStatus(SleepStatusSnapshot *snapshot);
void abortPending();

}

#endif
