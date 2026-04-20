#pragma once

#include <stddef.h>

namespace boot::provisioning {

bool isEnabled(void);

void start(void);
bool isProvisioned(void);
void reset(void);

#ifdef PIO_UNIT_TESTING
void test(void);
#endif

} // namespace boot::provisioning
