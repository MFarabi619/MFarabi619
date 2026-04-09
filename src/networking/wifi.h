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

// Access point
void wifi_start_ap(void);
void wifi_stop_ap(void);
bool wifi_is_ap_active(void);
void wifi_dns_service(void);

// AP configuration (persisted to NVS)
void wifi_get_ap_ssid(char *buf, size_t len);
void wifi_get_ap_password(char *buf, size_t len);
void wifi_set_ap_config(const char *ssid, const char *password);
bool wifi_get_ap_enabled(void);
void wifi_set_ap_enabled(bool enabled);

#endif // NETWORKING_WIFI_H
