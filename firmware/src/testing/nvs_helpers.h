#ifndef TESTING_NVS_HELPERS_H
#define TESTING_NVS_HELPERS_H

#ifdef PIO_UNIT_TESTING

#include "../config.h"
#include "../util/preferences_guard.h"

struct NvsStringSnapshot {
  char value[128];
  bool exists;
};

struct NvsBoolSnapshot {
  bool value;
  bool exists;
};

static inline void nvs_snapshot_string(Preferences &prefs, const char *key,
                                       NvsStringSnapshot *snap) {
  snap->exists = prefs.isKey(key);
  if (snap->exists) {
    prefs.getString(key, snap->value, sizeof(snap->value));
  } else {
    snap->value[0] = '\0';
  }
}

static inline void nvs_snapshot_bool(Preferences &prefs, const char *key,
                                     NvsBoolSnapshot *snap, bool default_val) {
  snap->exists = prefs.isKey(key);
  snap->value = prefs.getBool(key, default_val);
}

static inline void nvs_restore_string(Preferences &prefs, const char *key,
                                      const NvsStringSnapshot *snap) {
  if (snap->exists) prefs.putString(key, snap->value);
}

static inline void nvs_restore_bool(Preferences &prefs, const char *key,
                                    const NvsBoolSnapshot *snap) {
  if (snap->exists) prefs.putBool(key, snap->value);
}

struct WifiNvsSnapshot {
  NvsStringSnapshot ap_ssid;
  NvsStringSnapshot ap_pass;
  NvsBoolSnapshot ap_on;
};

static inline void wifi_nvs_save(WifiNvsSnapshot *snap) {
  PreferencesGuard prefs(config::wifi::NVS_NAMESPACE, true);
  if (!prefs.ok()) return;
  nvs_snapshot_string(prefs.ref(), "ap_ssid", &snap->ap_ssid);
  nvs_snapshot_string(prefs.ref(), "ap_pass", &snap->ap_pass);
  nvs_snapshot_bool(prefs.ref(), "ap_on", &snap->ap_on, true);
}

static inline void wifi_nvs_restore(const WifiNvsSnapshot *snap) {
  PreferencesGuard prefs(config::wifi::NVS_NAMESPACE, false);
  if (!prefs.ok()) return;
  prefs->clear();
  nvs_restore_string(prefs.ref(), "ap_ssid", &snap->ap_ssid);
  nvs_restore_string(prefs.ref(), "ap_pass", &snap->ap_pass);
  nvs_restore_bool(prefs.ref(), "ap_on", &snap->ap_on);
}

#endif
#endif
