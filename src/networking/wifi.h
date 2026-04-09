#ifndef NETWORKING_WIFI_H
#define NETWORKING_WIFI_H

#include "../config.h"
#include <stdbool.h>
#include <stddef.h>

void wifi_setup(void);
bool wifi_connect(void);
bool wifi_is_connected(void);

bool wifi_get_ssid(char *buf, size_t len);
bool wifi_get_password(char *buf, size_t len);
void wifi_set_credentials(const char *ssid, const char *password);

#endif // NETWORKING_WIFI_H
