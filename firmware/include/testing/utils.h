#pragma once

#ifdef PIO_UNIT_TESTING

#include <unity.h>
#include <string.h>
#include <config.h>
#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include <i2c.h>

// ─────────────────────────────────────────────────────────────────────────────
//  it() — BDD-style test runner macro
// ─────────────────────────────────────────────────────────────────────────────

static char _it_buf[256];
static inline void _it_run(void (*func)(void), const char *desc, int line) {
  strncpy(_it_buf, desc, sizeof(_it_buf) - 1);
  _it_buf[sizeof(_it_buf) - 1] = '\0';
  for (char *p = _it_buf; *p; p++) {
    if (*p == ' ') *p = '_';
  }
  UnityDefaultTestRun(func, _it_buf, line);
}

#define it(description, test_func) \
  _it_run(test_func, description, __LINE__)

// ─────────────────────────────────────────────────────────────────────────────
//  I2C helpers
// ─────────────────────────────────────────────────────────────────────────────

static inline void test_ensure_wire0(void) {
  Wire.begin(config::i2c::BUS_0.sda_gpio, config::i2c::BUS_0.scl_gpio,
             config::i2c::FREQUENCY_KHZ * 1000);
  Wire.setTimeOut(100);
}

static inline void test_ensure_wire1(void) {
  Wire1.begin(config::i2c::BUS_1.sda_gpio, config::i2c::BUS_1.scl_gpio,
              config::i2c::FREQUENCY_KHZ * 1000);
  Wire1.setTimeOut(100);
}

static inline void test_ensure_wire1_with_power(void) {
  hardware::i2c::enable();
  test_ensure_wire1();
}

// ─────────────────────────────────────────────────────────────────────────────
//  NVS snapshot/restore helpers
// ─────────────────────────────────────────────────────────────────────────────

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
  NvsStringSnapshot sta_ssid;
  NvsStringSnapshot sta_pass;
  NvsStringSnapshot ap_ssid;
  NvsStringSnapshot ap_pass;
  NvsBoolSnapshot ap_on;
};

static inline void wifi_nvs_save(WifiNvsSnapshot *snap) {
  Preferences prefs;
  if (!prefs.begin(config::wifi::NVS_NAMESPACE, true)) return;
  nvs_snapshot_string(prefs, "sta_ssid", &snap->sta_ssid);
  nvs_snapshot_string(prefs, "sta_pass", &snap->sta_pass);
  nvs_snapshot_string(prefs, "ap_ssid", &snap->ap_ssid);
  nvs_snapshot_string(prefs, "ap_pass", &snap->ap_pass);
  nvs_snapshot_bool(prefs, "ap_on", &snap->ap_on, true);
  prefs.end();
}

static inline void wifi_nvs_restore(const WifiNvsSnapshot *snap) {
  Preferences prefs;
  if (!prefs.begin(config::wifi::NVS_NAMESPACE, false)) return;
  prefs.clear();
  nvs_restore_string(prefs, "sta_ssid", &snap->sta_ssid);
  nvs_restore_string(prefs, "sta_pass", &snap->sta_pass);
  nvs_restore_string(prefs, "ap_ssid", &snap->ap_ssid);
  nvs_restore_string(prefs, "ap_pass", &snap->ap_pass);
  nvs_restore_bool(prefs, "ap_on", &snap->ap_on);
  prefs.end();
}

#endif
