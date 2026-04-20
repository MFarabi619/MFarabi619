#pragma once
#include <config.h>

namespace networking::ota {

void initialize(void);
void service(void);
bool isInProgress(void);

} // namespace networking::ota

