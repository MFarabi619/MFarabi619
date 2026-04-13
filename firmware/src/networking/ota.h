#ifndef NETWORKING_OTA_H
#define NETWORKING_OTA_H

#include "../config.h"

namespace networking::ota {

void initialize(void);
void service(void);
bool isInProgress(void);

} // namespace networking::ota

#endif
