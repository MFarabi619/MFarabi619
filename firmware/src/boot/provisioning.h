#pragma once

#include <stddef.h>

namespace boot::provisioning {

[[nodiscard]] bool isEnabled(void);

void start(void);
[[nodiscard]] bool isProvisioned(void);
void reset(void);

[[nodiscard]] bool accessUsername(char *buf, size_t len);
[[nodiscard]] bool accessAPIKey(char *buf, size_t len);
[[nodiscard]] bool accessDeviceName(char *buf, size_t len);

#ifdef PIO_UNIT_TESTING
void test(void);
#endif

} // namespace boot::provisioning
