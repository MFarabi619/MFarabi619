#pragma once

#include <stddef.h>

namespace boot::provisioning {

[[nodiscard]] bool isEnabled(void);

void start(void);
[[nodiscard]] bool isProvisioned(void);
void reset(void);

#ifdef PIO_UNIT_TESTING
void test(void);
#endif

} // namespace boot::provisioning
