#ifndef NETWORKING_UPDATE_H
#define NETWORKING_UPDATE_H

#include "../config.h"
#include <stddef.h>

bool update_from_sd(const char *path = CONFIG_OTA_SD_PATH);
bool update_from_url(const char *url, const char *cert_pem = nullptr);
bool update_can_rollback(void);
bool update_rollback(void);

void update_check_sd_on_boot(void);

#endif
