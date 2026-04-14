#ifndef NETWORKING_UPDATE_H
#define NETWORKING_UPDATE_H

#include "../config.h"
#include <stddef.h>

namespace networking::update {

bool applyFromSD(const char *path = config::ota::SD_PATH);
bool applyFromURL(const char *url, const char *cert_pem = nullptr);
bool canRollback();
bool rollback();

void checkSDOnBoot();

} // namespace networking::update

#endif
