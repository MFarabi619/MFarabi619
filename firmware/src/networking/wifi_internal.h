#ifndef NETWORKING_WIFI_INTERNAL_H
#define NETWORKING_WIFI_INTERNAL_H

#include "wifi.h"

#include <Preferences.h>

namespace networking::wifi::internal {

extern bool mdns_started;
extern bool ap_active;
extern const char wifi_ssid_slot[33];
extern const char wifi_pass_slot[65];

bool openPreferences(bool readonly, Preferences *prefs);
void configureMdnsServices(const char *hostname);

}

#endif
