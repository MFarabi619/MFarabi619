#ifndef NETWORKING_UPDATE_H
#define NETWORKING_UPDATE_H

#include "../config.h"
#include <stddef.h>

namespace networking::update {

bool applyFromSD(const char *path = config::ota::SD_PATH) noexcept;
bool applyFromURL(const char *url, const char *cert_pem = nullptr) noexcept;
[[nodiscard]] bool canRollback() noexcept;
bool rollback() noexcept;

void checkSDOnBoot() noexcept;

} // namespace networking::update

#endif
