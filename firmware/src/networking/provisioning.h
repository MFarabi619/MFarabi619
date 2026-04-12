#pragma once

#include <stddef.h>

namespace networking::provisioning {

void start(void);
[[nodiscard]] bool isProvisioned(void);
void reset(void);

[[nodiscard]] bool accessUsername(char *buf, size_t len);
[[nodiscard]] bool accessAPIKey(char *buf, size_t len);
[[nodiscard]] bool accessDeviceName(char *buf, size_t len);

#ifdef PIO_UNIT_TESTING
void test(void);
#endif

} // namespace networking::provisioning
